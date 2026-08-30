# FPGA ECG Signal Analyzer & Real-Time AI Telemetry Hardware Guide
**Target FPGA Board:** Terasic DE10-Lite (Intel MAX 10 `10M50DAF484C7G`)  
**Development Tool:** Quartus Prime Lite Edition (v20.1 or later)

---

## 1. Hardware Pinout & Wiring Connections

### A. CP2102 USB-to-UART Bridge (Host Interface)
Connect the CP2102 adapter to the DE10-Lite **JP1 GPIO Header**:

| CP2102 Pin | DE10-Lite Pin | FPGA Pin | Signal Description |
| :--- | :--- | :--- | :--- |
| **RXD** | GPIO[0] (Pin 1) | `PIN_V10` | FPGA Telemetry Transmit (`UART_TXD`) |
| **TXD** | GPIO[1] (Pin 2) | `PIN_W10` | FPGA Receiver Line (`UART_RXD`) |
| **GND** | GND (Pin 12) | `GND` | Common Ground Reference |
| **5V / 3.3V**| 3.3V (Pin 29) | `3.3V` | Board VCC Reference |

### B. AD8232 ECG Heart Rate Monitor Front-End
Connect the AD8232 module to the DE10-Lite **Arduino Header / ADC Header**:

| AD8232 Module | DE10-Lite Header | FPGA Pin | Signal Function |
| :--- | :--- | :--- | :--- |
| **OUTPUT** | ADC_IN1 / A0 | `PIN_C7` | Analog ECG Signal (0V - 3.3V centered @ 1.65V) |
| **3.3V** | 3V3 Header Pin | `3.3V` | 3.3V Supply Power |
| **GND** | GND Header Pin | `GND` | System Ground |
| **LO+ / LO-**| GPIO Header / N/C | N/C | Leads Off Detection (Optional) |

---

## 2. Quartus Prime Synthesis & Compilation Setup

### Step 1: Create Project & Import Verilog Files
1. Launch **Quartus Prime Lite Edition**.
2. Select **File -> New Project Wizard**.
3. Set project directory to your repository path and name top entity: `top_level`.
4. Select Device Family: **MAX 10 (DA/DF/SA/SF)** -> Device: **10M50DAF484C7G**.
5. Add source HDL files from `hdl/`:
   - `hdl/top_level.v`
   - `hdl/fir_filter.v`
   - `hdl/qrs_detector.v`
   - `hdl/uart_tx_fsm.v`
   - `hdl/uart_tx.v`

### Step 2: Assign Pins via QSF / Pin Planner
Import the provided `DE10_Lite.qsf` file or assign pins via **Assignments -> Pin Planner**:
- `MAX10_CLK1_50` -> `PIN_P11` (50 MHz Clock, 3.3-V LVTTL)
- `KEY[0]` -> `PIN_B8` (Active Low Reset)
- `KEY[1]` -> `PIN_A7` (Filter Bypass Toggle)
- `UART_TXD` -> `PIN_V10` (GPIO[0])
- `UART_RXD` -> `PIN_W10` (GPIO[1])
- `ADC_IN1` -> `PIN_C7` (Analog Input)

### Step 3: Run Synthesis & Fitter
Click **Processing -> Start Compilation** (Ctrl+L).  
Upon successful compilation, Quartus will generate:
- `output_files/top_level.sof` (SRAM Object File for volatile JTAG debugging)
- `output_files/top_level.pof` (Programmer Object File for non-volatile flash boot)

---

## 3. FPGA Flashing & Persistent Boot Guide

### Mode 1: Volatile SRAM Live Debugging (`.sof`)
1. Connect the DE10-Lite to host PC via USB-Blaster port.
2. Open **Tools -> Programmer** in Quartus Prime.
3. Select Hardware Setup: **USB-Blaster [USB-0]**.
4. Set Mode: **JTAG**.
5. Click **Add File** and select `output_files/top_level.sof`.
6. Check **Program/Configure** checkbox and click **Start**.
7. *Result:* Board runs the code immediately. (Resets when powered off).

---

### Mode 2: Non-Volatile Internal CFM Flash Boot (`.pof`)
To configure the MAX 10 FPGA to **auto-boot instantly on power-up**:

1. Open **Tools -> Programmer** in Quartus.
2. Set Mode: **Internal Configuration** (or **JTAG** with CFM target).
3. Click **Add File** and select `output_files/top_level.pof` (or convert `.sof` to `.pof` via *File -> Convert Programming Files* selecting CFM0/CFM1/CFM2 Internal Flash).
4. Select **CFM0** (Configuration Flash Memory) target location.
5. Check **Program/Configure** and **Verify** checkboxes.
6. Click **Start** to flash the internal NOR flash.
7. *Result:* Disconnect USB-Blaster; cycle power. The DE10-Lite board will auto-load the ECG analyzer pipeline in under 10 milliseconds upon power-up.

---

## 4. Connecting Web Dashboard to Hardware
1. Connect CP2102 USB UART adapter to your host machine's USB port.
2. Open `index.html` in a Web Serial API compatible browser (Google Chrome, Microsoft Edge, or Opera).
3. Select **115200 Baud** from the UART dropdown menu.
4. Click **Connect CP2102 Board** and pick the Silicon Labs CP2102 COM port.
5. Observe live 500 Hz streaming ECG trace and real-time AI diagnostic classification!
