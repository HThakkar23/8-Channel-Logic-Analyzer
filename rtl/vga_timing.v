`timescale 1ns / 1ps
//
// Generates 640x480 VGA timing at a 25 MHz pixel clock, following the
// standard VESA numbers (800 total pixels a line, 525 total lines, sync
// pulses active low). Two free running counters do all the work; hsync,
// vsync, active and the pixel coordinates are all just combinational
// functions of where those counters currently sit, so there is no extra
// latency between a counter value and the signals derived from it.
//
// frame_tick pulses for one cycle at the start of every frame. This
// project does not need it crossed into the system clock domain (no
// frame counter stat here), so it is left unused by the top level.
//
// Reused unchanged from the uart-vga-terminal project.
//
module vga_timing (
    input  wire clk_pix,
    input  wire rst,

    output wire hsync,
    output wire vsync,
    output wire active,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y,
    output reg         frame_tick
);

    localparam H_ACTIVE = 640;
    localparam H_FP      = 16;
    localparam H_SYNC    = 96;
    localparam H_BP      = 48;
    localparam H_TOTAL   = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE = 480;
    localparam V_FP      = 10;
    localparam V_SYNC    = 2;
    localparam V_BP      = 33;
    localparam V_TOTAL   = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    wire h_last = (h_cnt == H_TOTAL - 1);
    wire v_last = (v_cnt == V_TOTAL - 1);

    always @(posedge clk_pix) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (h_last) begin
            h_cnt <= 10'd0;
            v_cnt <= v_last ? 10'd0 : (v_cnt + 1'b1);
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    always @(posedge clk_pix) begin
        if (rst)
            frame_tick <= 1'b0;
        else
            frame_tick <= h_last && v_last;
    end

    assign hsync = ~((h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC));
    assign vsync = ~((v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC));
    assign active = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;

endmodule
