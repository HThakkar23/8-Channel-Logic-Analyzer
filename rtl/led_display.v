`timescale 1ns / 1ps
//
// Front panel status, all in the system clock domain, so nothing here
// needs a clock domain crossing.
//
//   led[0]   armed     - a capture is running, collecting the pre-trigger half
//   led[1]   triggered - the trigger condition has fired
//   led[2]   done      - a full capture is sitting in the buffer, ready to dump
//   led[3]   heartbeat - toggles at roughly 1 Hz, proof the design is alive at all
//   led[4]   activity  - toggles every sample tick, so it visibly slows down or
//                        speeds up as the host changes the sample rate divider
//   led[7:5] trig_channel, the probe channel currently armed to trigger on
//   led[9:8] trig_mode, the trigger condition currently configured
//
module led_display #(
    parameter integer CLK_FREQ_HZ = 100_000_000
) (
    input  wire       clk,
    input  wire       rst,

    input  wire       armed,
    input  wire       triggered,
    input  wire       done,
    input  wire       sample_tick,
    input  wire [2:0] trig_channel,
    input  wire [1:0] trig_mode,

    output wire [9:0] led
);

    localparam integer HEARTBEAT_HALF_PERIOD = CLK_FREQ_HZ / 2; // toggles twice a second
    localparam integer HB_CNT_WIDTH = $clog2(HEARTBEAT_HALF_PERIOD);

    reg [HB_CNT_WIDTH-1:0] hb_cnt;
    reg heartbeat;
    reg activity;

    always @(posedge clk) begin
        if (rst) begin
            hb_cnt    <= {HB_CNT_WIDTH{1'b0}};
            heartbeat <= 1'b0;
        end else if (hb_cnt == HEARTBEAT_HALF_PERIOD - 1) begin
            hb_cnt    <= {HB_CNT_WIDTH{1'b0}};
            heartbeat <= ~heartbeat;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst)
            activity <= 1'b0;
        else if (sample_tick)
            activity <= ~activity;
    end

    assign led[0]   = armed;
    assign led[1]   = triggered;
    assign led[2]   = done;
    assign led[3]   = heartbeat;
    assign led[4]   = activity;
    assign led[7:5] = trig_channel;
    assign led[9:8] = trig_mode;

endmodule
