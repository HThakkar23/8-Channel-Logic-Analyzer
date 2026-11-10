`timescale 1ns / 1ps
//
// 8N1 UART transmitter.
//
// This has its own bit period counter rather than sharing the receiver's
// 16x oversample tick. Sharing it is a common shortcut, but the oversample
// tick free runs with no fixed phase relationship to tx_start, so the
// first bit of a transmission could come out anywhere from a few percent
// to a full bit period short. Starting a fresh counter the moment a
// transmission begins keeps every bit, including the start bit, exactly
// one nominal period wide.
//
// Reused unchanged from the uart-vga-terminal project. cmd_protocol.v
// drives tx_start/tx_data the same careful way that project's self test
// mode did: only ever pulsing tx_start while tx_busy reads low, never off
// an edge-detected guess at when the last byte finished.
//
module uart_tx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire clk,
    input  wire rst,

    input  wire       tx_start,
    input  wire [7:0] tx_data,

    output reg  tx_pin,
    output reg  tx_busy
);

    localparam integer BIT_PERIOD = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer CNT_WIDTH  = $clog2(BIT_PERIOD);

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [CNT_WIDTH-1:0] bit_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    wire bit_done = (bit_cnt == BIT_PERIOD - 1);

    always @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            tx_pin  <= 1'b1;
            tx_busy <= 1'b0;
            bit_cnt <= {CNT_WIDTH{1'b0}};
            bit_idx <= 3'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tx_pin    <= 1'b0; // start bit begins now
                        bit_cnt   <= {CNT_WIDTH{1'b0}};
                        state     <= ST_START;
                    end
                end

                ST_START: begin
                    if (bit_done) begin
                        bit_cnt <= {CNT_WIDTH{1'b0}};
                        bit_idx <= 3'd0;
                        tx_pin  <= shift_reg[0];
                        state   <= ST_DATA;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    if (bit_done) begin
                        bit_cnt <= {CNT_WIDTH{1'b0}};
                        if (bit_idx == 3'd7) begin
                            tx_pin <= 1'b1; // stop bit
                            state  <= ST_STOP;
                        end else begin
                            shift_reg <= {1'b0, shift_reg[7:1]};
                            tx_pin    <= shift_reg[1];
                            bit_idx   <= bit_idx + 1'b1;
                        end
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (bit_done) begin
                        tx_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
