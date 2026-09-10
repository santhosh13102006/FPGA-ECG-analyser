# ESP32 ECG Signal Analyzer Firmware & Flashing Guide

## 1. Hardware Connections for 30-Pin ESP32 DevKit V1

Connect your AD8232 ECG sensor to the pins labeled on your 30-pin ESP32 DevKit board:

| AD8232 Pin | 30-Pin ESP32 DevKit Board Label | ESP32 GPIO Pin | Function |
| :--- | :--- | :--- | :--- |
| **OUTPUT** | **D34** (or **VP**) | `GPIO 34` | Analog ECG Signal Input (0 - 3.3V) |
| **LO+** | **D35** | `GPIO 35` | Leads-Off Detection (+) |
| **LO-** | **D32** | `GPIO 32` | Leads-Off Detection (-) |
| **3.3V** | **3V3** | `3.3V` | Power supply |
| **GND** | **GND** | `GND` | Common Ground |

*Optional:* Connect a push button between `GPIO 4` and `GND` to manually force Synthetic Waveform Mode.

---

## 2. Flashing via Arduino IDE

1. Open **Arduino IDE** (v1.8.x or v2.x).
2. Go to **File -> Preferences**. In *Additional Boards Manager URLs*, add:
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
3. Open **Tools -> Board -> Boards Manager**, search for `esp32` by Espressif Systems and click **Install**.
4. Select your Board: **Tools -> Board -> ESP32 Arduino -> ESP32 Dev Module** (or your specific board).
5. Select Port: **Tools -> Port -> /dev/ttyUSB0** or `COMx`.
6. Open `esp32/esp32_ecg_analyzer.ino`.
7. Click **Upload** (or press and hold the `BOOT` button on your ESP32 board when `Connecting...` appears).

---

## 3. Flashing via PlatformIO (CLI / VSCode)

Create a `platformio.ini` in the `esp32/` folder:

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
```

Run compilation and upload:
```bash
pio run --target upload
```

---

## 4. Connecting ESP32 to Web Dashboard

1. Connect ESP32 to host machine via Micro-USB / USB-C cable (built-in CP2102 or CH340 chip).
2. Open `index.html` (or `http://localhost:8080`) in Chrome, Edge, or Opera.
3. Click **LIVE STREAMING** mode button.
4. Select **115200 Baud** from the UART dropdown menu.
5. Click **Connect CP2102 / ESP32 Board** and select the Silicon Labs or CH340 serial port.
6. The dashboard will instantly stream and analyze live 500 Hz ECG signals from the ESP32!
