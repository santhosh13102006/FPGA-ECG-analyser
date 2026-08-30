// Synthesizable Top-Level Module: FPGA ECG Signal Analyzer & Telemetry Core
// Target Hardware: Terasic DE10-Lite FPGA Board (Intel MAX 10 10M50DAF484C7G)

module top_level (
    input  wire        MAX10_CLK1_50, // 50 MHz Onboard Crystal Oscillator
    input  wire [1:0]  KEY,           // KEY[0]: Reset (Active Low), KEY[1]: Filter Bypass
    input  wire [1:0]  SW,            // SW[0]: ADC vs Sim Mode, SW[1]: High Noise Inject
    output wire [9:0]  LEDR,          // Status Indicators & Diagnostic LEDs
    output wire        UART_TXD,      // CP2102 UART Transmit Line
    input  wire        UART_RXD       // CP2102 UART Receive Line
);

    // Active Low Reset Synchronization
    wire rst_n = KEY[0];
    
    // 500 Hz Sampling Frequency Generator (50 MHz / 100,000 = 500 Hz)
    reg [16:0] sample_cnt;
    reg        sample_tick;
    localparam SAMPLE_DIV = 100000;

    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt  <= 17'd0;
            sample_tick <= 1'b0;
        end else if (sample_cnt == SAMPLE_DIV - 1) begin
            sample_cnt  <= 17'd0;
            sample_tick <= 1'b1;
        end else begin
            sample_cnt  <= sample_cnt + 1'b1;
            sample_tick <= 1'b0;
        end
    end

    // Synthetic AD8232 Signal Synthesizer (for simulation / standalone test)
    reg [11:0] raw_adc_data;
    reg [15:0] synth_phase;

    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            synth_phase  <= 0;
            raw_adc_data <= 12'd2048;
        end else if (sample_tick) begin
            synth_phase <= (synth_phase >= 499) ? 0 : synth_phase + 1'b1;
            
            // Baseline 2048 (1.65V center)
            if (synth_phase > 240 && synth_phase < 260) 
                raw_adc_data <= 12'd3800; // R Peak
            else if (synth_phase >= 230 && synth_phase <= 240)
                raw_adc_data <= 12'd1200; // Q Dip
            else if (synth_phase >= 260 && synth_phase <= 270)
                raw_adc_data <= 12'd1500; // S Dip
            else if (synth_phase >= 320 && synth_phase <= 380)
                raw_adc_data <= 12'd2450; // T Wave
            else if (synth_phase >= 180 && synth_phase <= 210)
                raw_adc_data <= 12'd2250; // P Wave
            else
                raw_adc_data <= 12'd2048 + (SW[1] ? (synth_phase[4:0] * 25) : (synth_phase[3:0] * 10));
        end
    end

    // 1. Moving Average FIR Filter Module
    wire [11:0] filtered_data;
    wire        filt_valid;

    fir_filter #(
        .DATA_WIDTH(12),
        .TAPS(16)
    ) u_fir_filter (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .sample_valid(sample_tick),
        .raw_sample(raw_adc_data),
        .filtered_sample(filtered_data),
        .filtered_valid(filt_valid)
    );

    // Filter bypass switch selection
    wire [11:0] active_filt_signal = (KEY[1] == 1'b0) ? raw_adc_data : filtered_data;

    // 2. Pan-Tompkins QRS & R-Peak Detector
    wire        r_peak_flag;
    wire [15:0] rr_ms;
    wire [15:0] bpm_val;
    wire [2:0]  pqrst_state;

    qrs_detector #(
        .DATA_WIDTH(12),
        .SAMPLE_RATE(500)
    ) u_qrs_detector (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .sample_valid(sample_tick),
        .filtered_sample(active_filt_signal),
        .r_peak_detected(r_peak_flag),
        .rr_interval_ms(rr_ms),
        .bpm(bpm_val),
        .pqrst_stage(pqrst_state)
    );

    // 3. UART Packet Streaming FSM
    wire tx_busy_flag;

    uart_tx_fsm #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(115200)
    ) u_uart_fsm (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .sample_tick(sample_tick),
        .raw_adc_sample(raw_adc_data),
        .filtered_sample(active_filt_signal),
        .r_peak_flag(r_peak_flag),
        .pqrst_state(pqrst_state),
        .tx_out(UART_TXD),
        .tx_busy(tx_busy_flag)
    );

    // Status LED Outputs
    assign LEDR[0]   = r_peak_flag;   // Flash on R-Peak
    assign LEDR[1]   = KEY[1];        // Filter ON/OFF
    assign LEDR[2]   = SW[0];         // Mode indicator
    assign LEDR[5:3] = pqrst_state;   // Active P-Q-R-S-T stage
    assign LEDR[9:6] = bpm_val[3:0];  // Lower bits of BPM

endmodule
