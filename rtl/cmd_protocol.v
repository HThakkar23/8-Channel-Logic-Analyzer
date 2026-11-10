`timescale 1ns / 1ps
//
// Host command parser and dump streamer. Everything about a capture, rate,
// trigger channel, trigger mode, and when to arm, comes in over UART as a
// short binary command instead of board switches: there are too many
// combinations here for a handful of switches to describe cleanly.
//
// Opcodes, one byte each, received from the host:
//   8'h01  ARM          - arm a new capture, no payload
//   8'h02  SET_DIVIDER  - 2 payload bytes, sample_tick divider, MSB first
//   8'h03  SET_TRIGGER  - 1 payload byte: [7:5]=channel [4:3]=mode [2:0]=unused
//   8'h04  STATUS       - no payload, replies with one status byte
//   8'h05  DUMP         - no payload, streams the full 4096 byte capture
//
// Every command other than DUMP replies with a single byte, ACK (8'hAA)
// on a recognized opcode or NACK (8'h00) on anything else. DUMP replies
// with the 4096 capture bytes back to back with no framing, oldest
// sample first, starting from window_base, since the host already knows
// the length and the ring's wrap point is meaningless to it.
//
// STATUS replies with {5'b0, done, triggered, armed}.
//
module cmd_protocol #(
    parameter integer ADDR_W = 12,
    parameter integer DEPTH  = 4096
) (
    input  wire clk,
    input  wire rst,

    // host link
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    output reg  [7:0] tx_data,
    output reg        tx_start,
    input  wire       tx_busy,

    // capture engine control
    output reg        arm_strobe,
    output reg [15:0] divider,
    output reg [2:0]  trig_channel,
    output reg [1:0]  trig_mode,
    input  wire       armed,
    input  wire       triggered,
    input  wire       done,
    input  wire [ADDR_W-1:0] window_base,

    // dump read port into capture_buffer port A (shared with capture_engine)
    output reg               dump_active,
    output reg [ADDR_W-1:0]  dump_addr,
    input  wire [7:0]        dump_rdata
);

    localparam [7:0] OP_ARM         = 8'h01;
    localparam [7:0] OP_SET_DIVIDER = 8'h02;
    localparam [7:0] OP_SET_TRIGGER = 8'h03;
    localparam [7:0] OP_STATUS      = 8'h04;
    localparam [7:0] OP_DUMP        = 8'h05;

    localparam [7:0] RESP_ACK  = 8'hAA;
    localparam [7:0] RESP_NACK = 8'h00;

    localparam ST_IDLE       = 3'd0;
    localparam ST_PAYLOAD    = 3'd1;
    localparam ST_APPLY      = 3'd2;
    localparam ST_SEND_BYTE  = 3'd3;
    localparam ST_DUMP_ADDR  = 3'd4;
    localparam ST_DUMP_WAIT  = 3'd5;
    localparam ST_DUMP_SEND  = 3'd6;

    reg [2:0] state;
    reg [7:0] opcode;
    reg [1:0] payload_idx;
    reg [7:0] payload [0:1];

    reg [ADDR_W-1:0] dump_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            opcode       <= 8'd0;
            payload_idx  <= 2'd0;
            arm_strobe   <= 1'b0;
            divider      <= 16'd1000; // 100 MHz / 1000 = 100 kHz default sample rate
            trig_channel <= 3'd0;
            trig_mode    <= 2'b00;
            tx_start     <= 1'b0;
            tx_data      <= 8'd0;
            dump_active  <= 1'b0;
            dump_addr    <= {ADDR_W{1'b0}};
            dump_cnt     <= {ADDR_W{1'b0}};
        end else begin
            arm_strobe <= 1'b0;
            tx_start   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    dump_active <= 1'b0;
                    if (rx_valid) begin
                        opcode <= rx_data;
                        case (rx_data)
                            OP_ARM, OP_STATUS, OP_DUMP: state <= ST_APPLY;
                            OP_SET_DIVIDER: begin
                                payload_idx <= 2'd0;
                                state       <= ST_PAYLOAD;
                            end
                            OP_SET_TRIGGER: begin
                                payload_idx <= 2'd0;
                                state       <= ST_PAYLOAD;
                            end
                            default: begin
                                tx_data  <= RESP_NACK;
                                tx_start <= 1'b1;
                                state    <= ST_IDLE;
                            end
                        endcase
                    end
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        payload[payload_idx] <= rx_data;
                        if ((opcode == OP_SET_DIVIDER && payload_idx == 2'd1) ||
                            (opcode == OP_SET_TRIGGER && payload_idx == 2'd0)) begin
                            state <= ST_APPLY;
                        end else begin
                            payload_idx <= payload_idx + 1'b1;
                        end
                    end
                end

                ST_APPLY: begin
                    case (opcode)
                        OP_ARM: begin
                            arm_strobe <= 1'b1;
                            tx_data    <= RESP_ACK;
                        end
                        OP_SET_DIVIDER: begin
                            divider <= {payload[0], payload[1]};
                            tx_data <= RESP_ACK;
                        end
                        OP_SET_TRIGGER: begin
                            trig_channel <= payload[0][7:5];
                            trig_mode    <= payload[0][4:3];
                            tx_data      <= RESP_ACK;
                        end
                        OP_STATUS: begin
                            tx_data <= {5'b0, done, triggered, armed};
                        end
                        OP_DUMP: begin
                            dump_active <= 1'b1;
                            dump_addr   <= window_base;
                            dump_cnt    <= {ADDR_W{1'b0}};
                        end
                        default: tx_data <= RESP_NACK;
                    endcase

                    if (opcode == OP_DUMP)
                        state <= ST_DUMP_ADDR;
                    else
                        state <= ST_SEND_BYTE;
                end

                ST_SEND_BYTE: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        state    <= ST_IDLE;
                    end
                end

                ST_DUMP_ADDR: begin
                    // one cycle for dump_addr to reach capture_buffer and come back as dump_rdata
                    state <= ST_DUMP_WAIT;
                end

                ST_DUMP_WAIT: begin
                    state <= ST_DUMP_SEND;
                end

                ST_DUMP_SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= dump_rdata;
                        tx_start <= 1'b1;
                        if (dump_cnt == DEPTH - 1) begin
                            dump_active <= 1'b0;
                            state       <= ST_IDLE;
                        end else begin
                            dump_cnt  <= dump_cnt + 1'b1;
                            dump_addr <= dump_addr + 1'b1;
                            state     <= ST_DUMP_ADDR;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
