`timescale 1ns / 1ps
//
// Turns the capture buffer into an 8 channel waveform display, one
// sample per pixel column, no decimation. The 4096 sample capture is
// deeper than 640 pixels can show at once, so this shows a fixed 640
// sample window instead of trying to decimate the rest down to fit.
//
// The window is centered on the trigger sample, 320 samples before it
// and 320 after, like a real oscilloscope. window_base already points
// at the oldest sample and the ring is a power of two deep, so sliding
// to any point in it is just addition that wraps for free.
//
module waveform_renderer #(
    parameter integer ADDR_W     = 12,
    parameter integer PRETRIGGER = 2048
) (
    input  wire        clk_pix,
    input  wire        rst_pix,

    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        active,

    input  wire [ADDR_W-1:0] window_base_pix,

    output wire [ADDR_W-1:0] render_addr,
    input  wire [7:0]        render_rdata,

    output reg  [9:0]  pixel_x_d,
    output reg  [9:0]  pixel_y_d,
    output reg         active_d,

    output wire        trace_on,
    output wire        marker_on
);

    localparam integer WINDOW_START = PRETRIGGER - 320; // puts the trigger sample at column 320
    localparam integer TRIGGER_COL  = 320;
    localparam integer LANE_HEIGHT  = 60;  // 480 active rows / 8 channels
    localparam integer HIGH_ROW     = 12;  // row within a lane drawn for a logic 1
    localparam integer LOW_ROW      = 48;  // row within a lane drawn for a logic 0

    // one address issued per column, read back one pixel clock later
    assign render_addr = window_base_pix + WINDOW_START + pixel_x;

    wire [7:0] samp_cur = render_rdata;
    reg  [7:0] samp_prev;

    always @(posedge clk_pix) begin
        if (rst_pix) begin
            pixel_x_d <= 10'd0;
            pixel_y_d <= 10'd0;
            active_d  <= 1'b0;
            samp_prev <= 8'd0;
        end else begin
            pixel_x_d <= pixel_x;
            pixel_y_d <= pixel_y;
            active_d  <= active;
            samp_prev <= samp_cur;
        end
    end

    wire [2:0] lane        = pixel_y_d / LANE_HEIGHT;
    wire [6:0] row_in_lane = pixel_y_d % LANE_HEIGHT;
    wire [6:0] target_row  = samp_cur[lane] ? HIGH_ROW[6:0] : LOW_ROW[6:0];

    // the trace sits flat at target_row, with a vertical stroke connecting
    // high to low on the one column where this channel's bit actually changed
    assign trace_on = active_d && (
                         (row_in_lane == target_row) ||
                         (samp_cur[lane] != samp_prev[lane] &&
                          row_in_lane >= HIGH_ROW[6:0] && row_in_lane <= LOW_ROW[6:0])
                       );

    // red tinted overlay: a vertical line at the trigger column, plus a
    // thin separator at the top of every channel lane
    assign marker_on = active_d && ((pixel_x_d == TRIGGER_COL) || (row_in_lane == 7'd0));

endmodule
