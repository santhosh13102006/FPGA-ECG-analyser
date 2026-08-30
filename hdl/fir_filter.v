// Moving Average FIR Filter (16-Tap) for ECG Signal Smoothing
// Target Hardware: Intel MAX 10 FPGA (DE10-Lite)
// Pipeline: Averages 16 consecutive 12-bit ADC samples to remove high-frequency muscle noise / powerline interference

module fir_filter #(
    parameter DATA_WIDTH = 12,
    parameter TAPS       = 16,
    parameter SHIFT_BITS = 4  // log2(TAPS)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  sample_valid,
    input  wire [DATA_WIDTH-1:0] raw_sample,
    output reg  [DATA_WIDTH-1:0] filtered_sample,
    output reg                   filtered_valid
);

    reg [DATA_WIDTH-1:0] shift_reg [0:TAPS-1];
    reg [DATA_WIDTH+SHIFT_BITS-1:0] sum;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum <= 0;
            filtered_sample <= 0;
            filtered_valid <= 0;
            for (i = 0; i < TAPS; i = i + 1) begin
                shift_reg[i] <= 0;
            end
        end else if (sample_valid) begin
            // Shift pipeline
            sum <= sum + raw_sample - shift_reg[TAPS-1];
            for (i = TAPS-1; i > 0; i = i - 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
            shift_reg[0] <= raw_sample;
            
            // Output moving average
            filtered_sample <= (sum + raw_sample - shift_reg[TAPS-1]) >> SHIFT_BITS;
            filtered_valid <= 1'b1;
        end else begin
            filtered_valid <= 1'b0;
        end
    end

endmodule
