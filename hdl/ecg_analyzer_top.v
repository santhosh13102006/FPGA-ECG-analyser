// Top-Level FPGA ECG Signal Analyzer Module
// Target Hardware: Intel MAX 10 FPGA (10M50DAF484C7G on DE10-Lite Board)
// On-Chip ADC (ADC128S022 or MAX 10 Dual ADC Core) + FIR Filter + UART Streaming

module ecg_analyzer_top (
    input  wire        MAX10_CLK1_50, // 50 MHz System Clock
    input  wire [1:0]  KEY,           // KEY[0]: Reset (Active Low), KEY[1]: Filter Enable Toggle
    input  wire [9:0]  SW,            // SW[0]: Sim Mode vs ADC Mode
    output wire [9:0]  LEDR,          // Diagnostic Status LEDs
    output wire        UART_TXD,      // CP2102 UART TX (to Web Dashboard)
    input  wire        UART_RXD       // CP2102 UART RX
);

    // Internal Signals
    wire rst_n = KEY[0];
    wire filter_en = KEY[1];
    
    // Sample Generator / ADC clock divider (500 Hz sample tick from 50 MHz clock)
    reg [16:0] sample_clk_cnt;
    reg        sample_tick;
    localparam TICK_DIV = 100000; // 50,000,000 / 500 = 100,000
    
    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            sample_clk_cnt <= 0;
            sample_tick <= 1'b0;
        end else if (sample_clk_cnt == TICK_DIV - 1) begin
            sample_clk_cnt <= 0;
            sample_tick <= 1'b1;
        end else begin
            sample_clk_cnt <= sample_clk_cnt + 1'b1;
            sample_tick <= 1'b0;
        end
    end
    
    // Synthetic / ADC Sample simulation generator
    reg [11:0] raw_adc_data;
    reg [15:0] synth_phase;
    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            synth_phase <= 0;
            raw_adc_data <= 12'd2048;
        end else if (sample_tick) begin
            synth_phase <= (synth_phase >= 499) ? 0 : synth_phase + 1'b1;
            // Synthetic baseline ECG shape with noise
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
                raw_adc_data <= 12'd2048 + (synth_phase[3:0] * 12); // Isoelectric line with high freq noise
        end
    end

    // Instantiation 1: FIR Moving Average Filter
    wire [11:0] filtered_adc_data;
    wire        filtered_valid;
    
    fir_filter #(
        .DATA_WIDTH(12),
        .TAPS(16)
    ) u_fir (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .sample_valid(sample_tick),
        .raw_sample(raw_adc_data),
        .filtered_sample(filtered_adc_data),
        .filtered_valid(filtered_valid)
    );

    // Instantiation 2: Peak Detector & Metric Estimator
    wire        r_peak;
    wire [15:0] rr_ms;
    wire [15:0] calc_bpm;
    wire [2:0]  wave_state;
    
    peak_detector u_peak (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .sample_valid(sample_tick),
        .sample_in(filtered_adc_data),
        .r_peak_detected(r_peak),
        .rr_interval_ms(rr_ms),
        .bpm(calc_bpm),
        .pqrst_state(wave_state)
    );

    // Instantiation 3: Packet Framing & UART Controller
    // Packet Structure (8 bytes): [0xA5, 0x5A, RAW_H, RAW_L, FILT_H, FILT_L, STATE_BPM, CHECKSUM]
    reg [2:0]  pkt_state;
    reg [7:0]  tx_byte;
    reg        tx_start;
    wire       tx_busy;
    wire       tx_done;
    
    reg [11:0] raw_latched;
    reg [11:0] filt_latched;
    reg [7:0]  chksum;

    uart_tx #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(115200)
    ) u_uart (
        .clk(MAX10_CLK1_50),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_byte),
        .tx_out(UART_TXD),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // Packetizing FSM
    always @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            pkt_state   <= 3'd0;
            tx_start    <= 1'b0;
            tx_byte     <= 8'd0;
            raw_latched <= 12'd0;
            filt_latched<= 12'd0;
            chksum      <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            case (pkt_state)
                3'd0: begin // Wait for sample tick
                    if (sample_tick) begin
                        raw_latched  <= raw_adc_data;
                        filt_latched <= filtered_adc_data;
                        pkt_state    <= 3'd1;
                    end
                end
                
                3'd1: begin // Send Sync 1 (0xA5)
                    if (!tx_busy) begin
                        tx_byte  <= 8'hA5;
                        tx_start <= 1'b1;
                        chksum   <= 8'hA5;
                        pkt_state<= 3'd2;
                    end
                end
                
                3'd2: begin // Send Sync 2 (0x5A)
                    if (tx_done) begin
                        tx_byte  <= 8'h5A;
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ 8'h5A;
                        pkt_state<= 3'd3;
                    end
                end
                
                3'd3: begin // Raw High Byte
                    if (tx_done) begin
                        tx_byte  <= {4'b0000, raw_latched[11:8]};
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ {4'b0000, raw_latched[11:8]};
                        pkt_state<= 3'd4;
                    end
                end
                
                3'd4: begin // Raw Low Byte
                    if (tx_done) begin
                        tx_byte  <= raw_latched[7:0];
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ raw_latched[7:0];
                        pkt_state<= 3'd5;
                    end
                end
                
                3'd5: begin // Filtered High Byte
                    if (tx_done) begin
                        tx_byte  <= {4'b0000, filt_latched[11:8]};
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ {4'b0000, filt_latched[11:8]};
                        pkt_state<= 3'd6;
                    end
                end
                
                3'd6: begin // Filtered Low Byte
                    if (tx_done) begin
                        tx_byte  <= filt_latched[7:0];
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ filt_latched[7:0];
                        pkt_state<= 3'd7;
                    end
                end
                
                3'd7: begin // Checksum Byte
                    if (tx_done) begin
                        tx_byte  <= chksum;
                        tx_start <= 1'b1;
                        pkt_state<= 3'd0;
                    end
                end
                
                default: pkt_state <= 3'd0;
            endcase
        end
    end

    // Status LED Assignment
    assign LEDR[0] = r_peak;
    assign LEDR[1] = filter_en;
    assign LEDR[2] = SW[0];
    assign LEDR[5:3] = wave_state;
    assign LEDR[9:6] = calc_bpm[3:0];

endmodule
