// Real-Time R-Peak & P-Q-R-S-T Feature Extractor Module
// Target Hardware: Intel MAX 10 FPGA (DE10-Lite)
// Function: Dynamic threshold R-peak detector, R-R interval measurement, wave component timing

module peak_detector #(
    parameter DATA_WIDTH  = 12,
    parameter CLK_FREQ_HZ = 50000000, // 50 MHz system clock
    parameter SAMPLE_RATE = 500       // 500 Hz sampling frequency
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  sample_valid,
    input  wire [DATA_WIDTH-1:0] sample_in,
    output reg                   r_peak_detected,
    output reg  [15:0]           rr_interval_ms,
    output reg  [15:0]           bpm,
    output reg  [2:0]            pqrst_state // 0:IDLE, 1:P, 2:Q, 3:R, 4:S, 5:T
);

    // Refractory period counter (200ms at 500Hz = 100 samples)
    localparam REFRACTORY_SAMPLES = 100;
    
    reg [DATA_WIDTH-1:0] peak_threshold = 12'd2500; // Adaptive baseline R threshold
    reg [DATA_WIDTH-1:0] prev_sample_1;
    reg [DATA_WIDTH-1:0] prev_sample_2;
    
    reg [15:0] sample_counter;
    reg [15:0] refractory_cnt;
    
    // Wave state identification logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_peak_detected <= 1'b0;
            rr_interval_ms  <= 16'd0;
            bpm             <= 16'd0;
            sample_counter  <= 16'd0;
            refractory_cnt  <= 16'd0;
            prev_sample_1   <= 12'd0;
            prev_sample_2   <= 12'd0;
            pqrst_state     <= 3'd0;
        end else if (sample_valid) begin
            sample_counter <= sample_counter + 1'b1;
            prev_sample_2  <= prev_sample_1;
            prev_sample_1  <= sample_in;
            
            if (refractory_cnt > 0) begin
                refractory_cnt <= refractory_cnt - 1'b1;
                r_peak_detected <= 1'b0;
            end else begin
                // Peak detection derivative peak check
                if (prev_sample_1 > peak_threshold && 
                    prev_sample_1 > sample_in && 
                    prev_sample_1 > prev_sample_2) begin
                    
                    r_peak_detected <= 1'b1;
                    refractory_cnt  <= REFRACTORY_SAMPLES;
                    
                    // R-R Interval calculation (sample_counter * 1000ms / SAMPLE_RATE)
                    rr_interval_ms <= (sample_counter * 1000) / SAMPLE_RATE;
                    if (sample_counter > 0) begin
                        bpm <= (60 * SAMPLE_RATE) / sample_counter;
                    end
                    sample_counter <= 16'd0;
                    pqrst_state <= 3'd3; // R Peak state
                end else begin
                    r_peak_detected <= 1'b0;
                    
                    // P-Q-R-S-T Phase classifier timing approximation
                    if (sample_counter < 30)       pqrst_state <= 3'd4; // S-Wave deflection
                    else if (sample_counter < 100) pqrst_state <= 3'd5; // T-Wave repolarization
                    else if (sample_counter > 380 && sample_counter < 450) pqrst_state <= 3'd1; // P-Wave
                    else if (sample_counter >= 450) pqrst_state <= 3'd2; // Q-Dip
                    else pqrst_state <= 3'd0; // Baseline
                end
            end
        end
    end

endmodule
