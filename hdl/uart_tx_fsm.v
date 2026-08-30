// UART Transmission Finite State Machine (FSM) Module
// Target Baud Rate: 115200 bps @ 50 MHz System Clock
// Streams 7-Byte Telemetry Frame: [SYNC1, SYNC2, RAW_H, RAW_L, FILT_H, FILT_L, CHECKSUM]

module uart_tx_fsm #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire [11:0] raw_adc_sample,
    input  wire [11:0] filtered_sample,
    input  wire        r_peak_flag,
    input  wire [2:0]  pqrst_state,
    output wire        tx_out,
    output wire        tx_busy
);

    // Internal UART Byte Transmitter
    reg        tx_start;
    reg  [7:0] tx_byte;
    wire       tx_done;

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx_core (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_byte),
        .tx_out(tx_out),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // FSM State Encoding
    localparam ST_IDLE    = 3'd0;
    localparam ST_SYNC1   = 3'd1;
    localparam ST_SYNC2   = 3'd2;
    localparam ST_RAW_H   = 3'd3;
    localparam ST_RAW_L   = 3'd4;
    localparam ST_FILT_H  = 3'd5;
    localparam ST_FILT_L  = 3'd6;
    localparam ST_CHKSUM  = 3'd7;

    reg [2:0] state;
    reg [11:0] raw_latched;
    reg [11:0] filt_latched;
    reg [7:0]  chksum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            tx_start     <= 1'b0;
            tx_byte      <= 8'd0;
            raw_latched  <= 12'd0;
            filt_latched <= 12'd0;
            chksum       <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (sample_tick) begin
                        raw_latched  <= raw_adc_sample;
                        filt_latched <= filtered_sample;
                        state        <= ST_SYNC1;
                    end
                end

                ST_SYNC1: begin
                    if (!tx_busy) begin
                        tx_byte  <= 8'hA5;
                        tx_start <= 1'b1;
                        chksum   <= 8'hA5;
                        state    <= ST_SYNC2;
                    end
                end

                ST_SYNC2: begin
                    if (tx_done) begin
                        tx_byte  <= 8'h5A;
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ 8'h5A;
                        state    <= ST_RAW_H;
                    end
                end

                ST_RAW_H: begin
                    if (tx_done) begin
                        // Package 4-bit high raw sample + 1-bit peak flag + 3-bit wave state
                        tx_byte  <= {r_peak_flag, pqrst_state, raw_latched[11:8]};
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ {r_peak_flag, pqrst_state, raw_latched[11:8]};
                        state    <= ST_RAW_L;
                    end
                end

                ST_RAW_L: begin
                    if (tx_done) begin
                        tx_byte  <= raw_latched[7:0];
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ raw_latched[7:0];
                        state    <= ST_FILT_H;
                    end
                end

                ST_FILT_H: begin
                    if (tx_done) begin
                        tx_byte  <= {4'b0000, filt_latched[11:8]};
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ {4'b0000, filt_latched[11:8]};
                        state    <= ST_FILT_L;
                    end
                end

                ST_FILT_L: begin
                    if (tx_done) begin
                        tx_byte  <= filt_latched[7:0];
                        tx_start <= 1'b1;
                        chksum   <= chksum ^ filt_latched[7:0];
                        state    <= ST_CHKSUM;
                    end
                end

                ST_CHKSUM: begin
                    if (tx_done) begin
                        tx_byte  <= chksum;
                        tx_start <= 1'b1;
                        state    <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
