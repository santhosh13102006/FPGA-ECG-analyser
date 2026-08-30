// UART Transmitter Module for ECG Packet Streaming
// Baud Rate: 115200 bps @ 50MHz Clock
// Framing: 8 data bits, 1 stop bit, no parity

module uart_tx #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_out,
    output reg        tx_busy,
    output reg        tx_done
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    localparam STATE_IDLE  = 3'b000;
    localparam STATE_START = 3'b001;
    localparam STATE_DATA  = 3'b010;
    localparam STATE_STOP  = 3'b011;
    
    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= STATE_IDLE;
            tx_out     <= 1'b1;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            clk_cnt    <= 0;
            bit_idx    <= 0;
            data_shift <= 8'd0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                STATE_IDLE: begin
                    tx_out  <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        state      <= STATE_START;
                        data_shift <= tx_data;
                        tx_busy    <= 1'b1;
                        clk_cnt    <= 0;
                    end
                end
                
                STATE_START: begin
                    tx_out <= 1'b0; // Start bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= STATE_DATA;
                    end
                end
                
                STATE_DATA: begin
                    tx_out <= data_shift[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1'b1;
                        end else begin
                            state <= STATE_STOP;
                        end
                    end
                end
                
                STATE_STOP: begin
                    tx_out <= 1'b1; // Stop bit
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= 0;
                        tx_done <= 1'b1;
                        state   <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
