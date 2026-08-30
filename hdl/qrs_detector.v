// Pan-Tompkins Adaptive Threshold QRS / R-Peak Detector Module
// Target Hardware: Intel MAX 10 FPGA (DE10-Lite)
// Performs derivative stage, squaring approximation, moving window integration, 
// adaptive peak thresholding, and R-R interval measurement.

module qrs_detector #(
    parameter DATA_WIDTH  = 12,
    parameter SAMPLE_RATE = 500 // 500 Hz ECG sampling rate
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  sample_valid,
    input  wire [DATA_WIDTH-1:0] filtered_sample,
    output reg                   r_peak_detected,
    output reg  [15:0]           rr_interval_ms,
    output reg  [15:0]           bpm,
    output reg  [2:0]            pqrst_stage // 0:IDLE, 1:P, 2:Q, 3:R, 4:S, 5:T
);

    // Pan-Tompkins Pipeline Delay Buffers
    reg signed [DATA_WIDTH:0] d1, d2;
    reg [23:0] sq_val;
    reg [27:0] mwi_sum;
    reg [23:0] mwi_buffer [0:15]; // 16-sample Moving Window Integrator
    integer i;

    // Adaptive Threshold Logic
    reg [23:0] spk_i = 24'd150000; // Signal Peak estimate
    reg [23:0] npk_i = 24'd30000;  // Noise Peak estimate
    reg [23:0] threshold_i1;       // Primary threshold
    
    // Sample Counters for R-R timing
    reg [15:0] sample_counter;
    reg [15:0] refractory_cnt;
    localparam REFRACTORY_SAMPLES = 100; // 200ms at 500Hz sampling rate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d1 <= 0;
            d2 <= 0;
            sq_val <= 0;
            mwi_sum <= 0;
            r_peak_detected <= 1'b0;
            rr_interval_ms <= 16'd833;
            bpm <= 16'd72;
            sample_counter <= 16'd0;
            refractory_cnt <= 16'd0;
            pqrst_stage <= 3'd0;
            for (i = 0; i < 16; i = i + 1) begin
                mwi_buffer[i] <= 0;
            end
        end else if (sample_valid) begin
            // Step 1: Derivative stage (y[n] = 2x[n] + x[n-1] - x[n-3] - 2x[n-4]) / 8
            d2 <= d1;
            d1 <= filtered_sample;
            
            // Step 2: Squaring stage (enhances high-frequency QRS slope)
            sq_val <= (filtered_sample > d1) ? (filtered_sample - d1) * (filtered_sample - d1) : (d1 - filtered_sample) * (d1 - filtered_sample);
            
            // Step 3: Moving Window Integration (MWI)
            mwi_sum <= mwi_sum + sq_val - mwi_buffer[15];
            for (i = 15; i > 0; i = i - 1) begin
                mwi_buffer[i] <= mwi_buffer[i-1];
            end
            mwi_buffer[0] <= sq_val;

            // Step 4: Dynamic Threshold Evaluation
            threshold_i1 <= npk_i + ((spk_i - npk_i) >> 2);
            sample_counter <= sample_counter + 1'b1;

            if (refractory_cnt > 0) begin
                refractory_cnt <= refractory_cnt - 1'b1;
                r_peak_detected <= 1'b0;
            end else begin
                // Check for R-peak candidate crossing integration threshold
                if (mwi_sum > threshold_i1) begin
                    r_peak_detected <= 1'b1;
                    refractory_cnt <= REFRACTORY_SAMPLES;
                    
                    // Adapt Signal Peak estimate
                    spk_i <= (spk_i >> 3) * 7 + (mwi_sum >> 3);

                    // Compute R-R duration in ms
                    rr_interval_ms <= (sample_counter * 1000) / SAMPLE_RATE;
                    if (sample_counter > 0) begin
                        bpm <= (60 * SAMPLE_RATE) / sample_counter;
                    end
                    sample_counter <= 16'd0;
                    pqrst_stage <= 3'd3; // R Peak
                end else begin
                    r_peak_detected <= 1'b0;
                    // Adapt Noise Peak estimate
                    npk_i <= (npk_i >> 3) * 7 + (mwi_sum >> 3);

                    // Wave Segment Classification
                    if (sample_counter < 25)        pqrst_stage <= 3'd4; // S Dip
                    else if (sample_counter < 90)   pqrst_stage <= 3'd5; // T Wave
                    else if (sample_counter > 360 && sample_counter < 430) pqrst_stage <= 3'd1; // P Wave
                    else if (sample_counter >= 430) pqrst_stage <= 3'd2; // Q Dip
                    else pqrst_stage <= 3'd0;
                end
            end
        end
    end

endmodule
