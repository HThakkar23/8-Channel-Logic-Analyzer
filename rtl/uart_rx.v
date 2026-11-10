`timescale 1ns / 1ps
//
// 8N1 UART receiver, 16x oversampling.
//
// The line is synchronized with a two flop chain before anything else
// touches it, since it comes from an external pin with no relationship to
// our clock. A start bit is confirmed by re-checking the line at the
// middle of its bit period (tick 8 of 16) rather than acting on the first
// falling edge, which rejects short glitches. Each data bit and the stop
// bit are then sampled at their own mid point, 16 ticks apart.
//
// Reused unchanged from the uart-vga-terminal project. Here it carries the
// host command bytes (ARM, SET_DIVIDER, SET_TRIGGER, STATUS, DUMP) instead
// of typed terminal characters, but the wire protocol underneath is
// identical, so there was no reason to touch this file.
//
module uart_rx (
    input  wire clk,
    input  wire rst,
    input  wire tick_16x,
    input  wire rx_pin,

    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_frame_err
);

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    reg rx_sync0, rx_sync1;

    always @(posedge clk) begin
        rx_sync0 <= rx_pin;
        rx_sync1 <= rx_sync0;
    end

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            tick_cnt     <= 4'd0;
            bit_idx      <= 3'd0;
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
            rx_data      <= 8'd0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!rx_sync1) begin
                        state    <= ST_START;
                        tick_cnt <= 4'd0;
                    end
                end

                ST_START: begin
                    if (tick_16x) begin
                        if (tick_cnt == 4'd7) begin
                            if (!rx_sync1) begin
                                state    <= ST_DATA;
                                tick_cnt <= 4'd0;
                                bit_idx  <= 3'd0;
                            end else begin
                                state <= ST_IDLE; // was just a glitch
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                ST_DATA: begin
                    if (tick_16x) begin
                        if (tick_cnt == 4'd15) begin
                            tick_cnt  <= 4'd0;
                            shift_reg <= {rx_sync1, shift_reg[7:1]};
                            if (bit_idx == 3'd7)
                                state <= ST_STOP;
                            else
                                bit_idx <= bit_idx + 1'b1;
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                ST_STOP: begin
                    if (tick_16x) begin
                        if (tick_cnt == 4'd15) begin
                            rx_data      <= shift_reg;
                            rx_valid     <= 1'b1;
                            rx_frame_err <= !rx_sync1; // stop bit should read high
                            state        <= ST_IDLE;
                            tick_cnt     <= 4'd0;
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
