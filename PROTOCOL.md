# FPGA ECG Signal Analyzer & Diagnostic Protocol Specification

## Target Hardware
* **FPGA Board:** Intel MAX 10 (10M50DAF484C7G on Terasic DE10-Lite)
* **Sampling Rate:** 500 Hz (2 ms period)
* **ADC Resolution:** 12-bit (0 - 4095 range, 0 - 3.3V reference)
* **Host Interface:** CP2102 USB-to-UART Bridge @ 115200 Baud (8N1)

---

## Binary UART Byte Packet Frame Format

Each telemetry frame transmitted from the FPGA to the Web Dashboard consists of **7 bytes**:

| Byte Index | Field Name | Description | Range / Format |
| :--- | :--- | :--- | :--- |
| **Byte 0** | `SYNC_0` | Synchronization Sync Byte 1 | `0xA5` |
| **Byte 1** | `SYNC_1` | Synchronization Sync Byte 2 | `0x5A` |
| **Byte 2** | `RAW_MSB` | Raw ADC Data High 4 bits | `0x00 - 0x0F` |
| **Byte 3** | `RAW_LSB` | Raw ADC Data Low 8 bits | `0x00 - 0xFF` |
| **Byte 4** | `FILT_MSB` | FIR Filtered Data High 4 bits | `0x00 - 0x0F` |
| **Byte 5** | `FILT_LSB` | FIR Filtered Data Low 8 bits | `0x00 - 0xFF` |
| **Byte 6** | `CHECKSUM` | XOR Checksum | Byte XOR sum of Bytes 0 through 5 |

### Checksum Verification Equation:
$$\text{Checksum} = \text{SYNC\_0} \oplus \text{SYNC\_1} \oplus \text{RAW\_MSB} \oplus \text{RAW\_LSB} \oplus \text{FILT\_MSB} \oplus \text{FILT\_LSB}$$

---

## Signal Processing & Wave Component Extraction
1. **FIR Filter:** 16-tap Moving Average pipeline running in real-time on FPGA hardware.
2. **P-Q-R-S-T Detection:** Dynamic derivative thresholding with 200 ms refractory period for R-peak indexing, coupled with timing window estimators for P-Wave, Q-Dip, S-Dip, and T-Wave.

---

## Diagnostic Rule Engine Matrix

| Condition | HR (BPM) | R-R Interval (ms) | Waveform Diagnostic Criteria | Clinical Action & Protocol |
| :--- | :--- | :--- | :--- | :--- |
| **Normal Sinus Rhythm** | 60 - 100 | 600 - 1000 | Normal P-Q-R-S-T morphology, standard ST segment | Routine monitoring, safe baseline. |
| **Sinus Bradycardia** | < 60 | > 1000 | Prolonged R-R interval, normal waveform shape | Administer Atropine (0.5mg IV), prepare transcutaneous pacemaker. |
| **Sinus Tachycardia** | > 100 | < 600 | Shortened R-R interval, normal PQRST complex | Administer Beta-blockers, vagal maneuvers, treat underlying cause. |
| **STEMI / Infarction** | Any | Variable | ST-segment elevation (>0.2 mV) & pathological deep Q-wave / T inversion | Chewable Aspirin (325mg) + Clopidogrel (600mg), Sublingual Nitroglycerin, immediate PCI within 90 mins. |
| **Atrial Fibrillation** | Variable | Irregular | Absent P-waves & irregular R-R interval spacing | Anticoagulation therapy, cardioversion / rate control (Diltiazem/Metoprolol). |
| **PVC (Premature Ventricular)**| Variable | Early peak | Wide QRS complex (>120 ms) & compensatory pause | Electrolyte balancing (K+, Mg2+), antiarrhythmic drugs (Amiodarone). |
| **Hyperkalemia** | Variable | Variable | Peaked/tented T-waves & prolonged PR interval | IV Calcium Gluconate, Insulin + Dextrose, Nebulized Albuterol. |
