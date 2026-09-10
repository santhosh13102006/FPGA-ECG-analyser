/*
 * ESP32 ECG Signal Analyzer & Real-Time Telemetry Core
 * Firmware for ESP32 (NodeMCU-32S / ESP32-WROOM-32)
 *
 * Hardware Connections:
 * - AD8232 OUTPUT -> ESP32 GPIO 36 (VP / ADC1_CH0)
 * - AD8232 LO+    -> ESP32 GPIO 34 (Input only)
 * - AD8232 LO-    -> ESP32 GPIO 35 (Input only)
 * - AD8232 3.3V   -> ESP32 3V3
 * - AD8232 GND    -> ESP32 GND
 *
 * Telemetry Output: 115200 Baud UART
 * Binary Frame (7 Bytes): [0xA5, 0x5A, RAW_H, RAW_L, FILT_H, FILT_L, CHECKSUM]
 */

#include <Arduino.h>

// Pin Definitions (Right-side single header configuration for 30-Pin DevKit V1)
// All 5 connections are grouped together on the top 5 pins of the RIGHT side!
#define ECG_ADC_PIN    4   // AD8232 OUTPUT -> Pin labeled D4  (5th pin down on RIGHT side)
#define LO_PLUS_PIN    15  // AD8232 LO+    -> Pin labeled D15 (3rd pin down on RIGHT side)
#define LO_MINUS_PIN   2   // AD8232 LO-    -> Pin labeled D2  (4th pin down on RIGHT side)
#define SIM_MODE_PIN   5   // Optional Sim Button -> Pin labeled D5 (8th pin down on RIGHT side)

// DSP & Sampling Parameters
#define SAMPLE_RATE_HZ 500
#define TIMER_INTERVAL_US (1000000 / SAMPLE_RATE_HZ) // 2000 us = 500 Hz
#define FIR_TAPS       16

// Global State
volatile bool sampleTick = false;
hw_timer_t * timer = NULL;
portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED;

// FIR Filter Buffer
uint16_t firShiftReg[FIR_TAPS] = {0};
uint32_t firSum = 0;
uint8_t firIdx = 0;

// Pan-Tompkins Peak Detector State
uint16_t sampleCounter = 0;
uint16_t refractoryCnt = 0;
uint32_t spkI = 150000;
uint32_t npkI = 30000;
uint16_t prevSample = 2048;
uint8_t  pqrstState = 0; // 0:IDLE, 1:P, 2:Q, 3:R, 4:S, 5:T
bool     rPeakFlag = false;

// Synthetic Generator Phase
uint16_t synthPhase = 0;
bool simModeActive = false;

// Timer ISR (500 Hz Tick)
void IRAM_ATTR onTimer() {
    portENTER_CRITICAL_ISR(&timerMux);
    sampleTick = true;
    portEXIT_CRITICAL_ISR(&timerMux);
}

// 16-Tap Moving Average FIR Filter
uint16_t applyFIRFilter(uint16_t rawSample) {
    firSum -= firShiftReg[firIdx];
    firShiftReg[firIdx] = rawSample;
    firSum += rawSample;
    firIdx = (firIdx + 1) % FIR_TAPS;
    return (uint16_t)(firSum / FIR_TAPS);
}

// Synthetic ECG Waveform Generator
uint16_t generateSyntheticSample() {
    synthPhase = (synthPhase + 1) % 500;
    uint16_t val = 2048; // Isoelectric baseline

    if (synthPhase > 180 && synthPhase < 210)      val += 200;  // P Wave
    else if (synthPhase >= 230 && synthPhase <= 240) val -= 300;  // Q Dip
    else if (synthPhase > 240 && synthPhase < 260)   val += 1600; // R Peak
    else if (synthPhase >= 260 && synthPhase <= 270) val -= 500;  // S Dip
    else if (synthPhase > 320 && synthPhase < 380)   val += 400;  // T Wave
    else val += random(-50, 50); // High-frequency muscle noise

    return constrain(val, 0, 4095);
}

// Peak Detection & Wave Anatomy Extractor
void processPeakDetection(uint16_t filtSample) {
    sampleCounter++;

    // MWI Approximation
    int32_t diff = abs((int32_t)filtSample - (int32_t)prevSample);
    uint32_t sqVal = diff * diff;
    prevSample = filtSample;

    uint32_t threshold = npkI + ((spkI - npkI) >> 2);

    if (refractoryCnt > 0) {
        refractoryCnt--;
        rPeakFlag = false;
    } else {
        if (sqVal > threshold) {
            rPeakFlag = true;
            refractoryCnt = 100; // 200 ms refractory at 500 Hz
            spkI = (spkI >> 3) * 7 + (sqVal >> 3);
            sampleCounter = 0;
            pqrstState = 3; // R-Peak
        } else {
            rPeakFlag = false;
            npkI = (npkI >> 3) * 7 + (sqVal >> 3);

            // Estimate P-Q-S-T wave states
            if (sampleCounter < 25)        pqrstState = 4; // S Dip
            else if (sampleCounter < 90)   pqrstState = 5; // T Wave
            else if (sampleCounter > 360 && sampleCounter < 430) pqrstState = 1; // P Wave
            else if (sampleCounter >= 430) pqrstState = 2; // Q Dip
            else pqrstState = 0;
        }
    }
}

// Binary UART Packet Transmitter (7 Bytes)
void sendTelemetryFrame(uint16_t rawSample, uint16_t filtSample) {
    uint8_t rawH = (rPeakFlag ? 0x80 : 0x00) | ((pqrstState & 0x07) << 4) | ((rawSample >> 8) & 0x0F);
    uint8_t rawL = rawSample & 0xFF;
    uint8_t filtH = (filtSample >> 8) & 0x0F;
    uint8_t filtL = filtSample & 0xFF;

    uint8_t chksum = 0xA5 ^ 0x5A ^ rawH ^ rawL ^ filtH ^ filtL;

    uint8_t packet[7] = { 0xA5, 0x5A, rawH, rawL, filtH, filtL, chksum };
    Serial.write(packet, 7);
}

void setup() {
    Serial.begin(115200);

    pinMode(ECG_ADC_PIN, INPUT);
    pinMode(LO_PLUS_PIN, INPUT);
    pinMode(LO_MINUS_PIN, INPUT);
    pinMode(SIM_MODE_PIN, INPUT_PULLUP);

    // ADC Configuration (12-Bit resolution: 0 - 4095)
    analogReadResolution(12);
    analogSetAttenuation(ADC_11db); // 0V to 3.3V range

    // 500 Hz Hardware Timer setup (compatible with ESP32 Core v2.x and v3.x)
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    timer = timerBegin(1000000); // 1 MHz timer resolution
    timerAttachInterrupt(timer, &onTimer);
    timerAlarm(timer, TIMER_INTERVAL_US, true, 0); // 2000 us interval, auto-reload
#else
    timer = timerBegin(0, 80, true); // 80 MHz / 80 = 1 MHz
    timerAttachInterrupt(timer, &onTimer, true);
    timerAlarmWrite(timer, TIMER_INTERVAL_US, true);
    timerAlarmEnable(timer);
#endif
}

void loop() {
    if (sampleTick) {
        portENTER_CRITICAL(&timerMux);
        sampleTick = false;
        portEXIT_CRITICAL(&timerMux);

        // Check leads off status or simulation mode button
        bool leadsOff = (digitalRead(LO_PLUS_PIN) == HIGH || digitalRead(LO_MINUS_PIN) == HIGH);
        bool btnPressed = (digitalRead(SIM_MODE_PIN) == LOW);

        uint16_t rawVal = 0;
        if (leadsOff || btnPressed || simModeActive) {
            rawVal = generateSyntheticSample();
        } else {
            rawVal = analogRead(ECG_ADC_PIN);
        }

        uint16_t filtVal = applyFIRFilter(rawVal);
        processPeakDetection(filtVal);
        sendTelemetryFrame(rawVal, filtVal);
    }
}
