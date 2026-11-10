`timescale 1ns / 1ps
//
// Drives the capture side of capture_buffer's port A. Four states: wait
// for an arm command, fill the pre-trigger half of the ring while
// watching for the trigger condition, fill the post-trigger half once it
// fires, then sit done until the host dumps the buffer or rearms.
//
// The buffer is a ring (DEPTH a power of two, ADDR_W matching it exactly)
// so write_ptr just free runs and wraps on its own through plain unsigned
// overflow. No modulo arithmetic anywhere in this module.
//
// Easy spot to get wrong: the sample that satisfies the trigger still
// counts as the first post-trigger sample, it is not free. post_cnt has
// to seed at 1, not 0, on the tick the trigger fires, or the total count
// comes up one short and window_base ends up pointing one sample early.
// Checked by hand on a small DEPTH=8, PRETRIGGER=4 case before trusting it.
//
module capture_engine #(
    parameter integer DEPTH      = 4096,
    parameter integer PRETRIGGER = 2048,
    parameter integer ADDR_W     = 12
) (
    input  wire       clk,
    input  wire       rst,

    input  wire       sample_tick,
    input  wire [7:0] probe_in,

    input  wire       arm_strobe,
    input  wire [2:0] trig_channel,
    input  wire [1:0] trig_mode,   // 00 rising edge, 01 falling edge, 10 level high, 11 free run

    output reg                capture_we,
    output reg  [ADDR_W-1:0]  capture_addr,
    output reg  [7:0]         capture_din,

    output wire               armed,
    output wire               triggered,
    output wire               done,
    output reg  [ADDR_W-1:0]  window_base
);

    localparam integer POST_REQUIRED = DEPTH - PRETRIGGER;

    localparam ST_IDLE      = 2'd0;
    localparam ST_ARMED     = 2'd1;
    localparam ST_TRIGGERED = 2'd2;
    localparam ST_DONE      = 2'd3;

    reg [1:0] state;
    reg [ADDR_W-1:0] write_ptr;
    reg [ADDR_W-1:0] prefill_cnt;
    reg primed;
    reg [ADDR_W-1:0] post_cnt;
    reg [7:0] prev_probe;

    assign armed     = (state == ST_ARMED);
    assign triggered = (state == ST_TRIGGERED) || (state == ST_DONE);
    assign done      = (state == ST_DONE);

    reg trig_hit_comb;
    always @* begin
        case (trig_mode)
            2'b00:   trig_hit_comb = primed &&  probe_in[trig_channel] && !prev_probe[trig_channel];
            2'b01:   trig_hit_comb = primed && !probe_in[trig_channel] &&  prev_probe[trig_channel];
            2'b10:   trig_hit_comb = primed &&  probe_in[trig_channel];
            default: trig_hit_comb = primed; // free run: fire as soon as the ring is primed
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            write_ptr    <= {ADDR_W{1'b0}};
            prefill_cnt  <= {ADDR_W{1'b0}};
            primed       <= 1'b0;
            post_cnt     <= {ADDR_W{1'b0}};
            prev_probe   <= 8'd0;
            window_base  <= {ADDR_W{1'b0}};
            capture_we   <= 1'b0;
            capture_addr <= {ADDR_W{1'b0}};
            capture_din  <= 8'd0;
        end else begin
            capture_we <= 1'b0; // default each cycle, the active states below override it

            case (state)
                ST_IDLE: begin
                    if (arm_strobe) begin
                        state       <= ST_ARMED;
                        write_ptr   <= {ADDR_W{1'b0}};
                        prefill_cnt <= {ADDR_W{1'b0}};
                        primed      <= 1'b0;
                        prev_probe  <= probe_in;
                    end
                end

                ST_ARMED: begin
                    if (sample_tick) begin
                        capture_we   <= 1'b1;
                        capture_addr <= write_ptr;
                        capture_din  <= probe_in;
                        prev_probe   <= probe_in;
                        write_ptr    <= write_ptr + 1'b1;

                        if (trig_hit_comb) begin
                            state    <= ST_TRIGGERED;
                            post_cnt <= {{(ADDR_W-1){1'b0}}, 1'b1}; // this write is post-trigger sample 1, not 0
                        end else if (!primed) begin
                            if (prefill_cnt == PRETRIGGER - 1)
                                primed <= 1'b1;
                            else
                                prefill_cnt <= prefill_cnt + 1'b1;
                        end
                    end
                end

                ST_TRIGGERED: begin
                    if (sample_tick) begin
                        capture_we   <= 1'b1;
                        capture_addr <= write_ptr;
                        capture_din  <= probe_in;
                        write_ptr    <= write_ptr + 1'b1;

                        if (post_cnt == POST_REQUIRED - 1) begin
                            state       <= ST_DONE;
                            window_base <= write_ptr + 1'b1; // oldest sample = next write address, ring is now full
                        end else begin
                            post_cnt <= post_cnt + 1'b1;
                        end
                    end
                end

                ST_DONE: begin
                    if (arm_strobe) begin
                        state       <= ST_ARMED;
                        write_ptr   <= {ADDR_W{1'b0}};
                        prefill_cnt <= {ADDR_W{1'b0}};
                        primed      <= 1'b0;
                        prev_probe  <= probe_in;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
