`timescale 1ns / 1ps
//
// True dual port sample memory, 4096 x 8 bits, one bit per probe channel.
// Port A is driven at the system clock: capture_engine writes samples in,
// cmd_protocol reads them back out during a dump. Port B is read at the
// pixel clock by waveform_renderer. At this size the buffer fits in one
// RAMB36 tile; see scripts/capture_budget.py for the exact math.
//
module capture_buffer #(
    parameter integer DEPTH   = 4096,
    parameter integer WIDTH   = 8,
    parameter integer ADDR_W  = 12
) (
    input  wire                  clk_a,
    input  wire                  clk_b,

    input  wire                  we_a,
    input  wire [ADDR_W-1:0]     addr_a,
    input  wire [WIDTH-1:0]      din_a,
    output reg  [WIDTH-1:0]      dout_a,

    input  wire                  we_b,
    input  wire [ADDR_W-1:0]     addr_b,
    input  wire [WIDTH-1:0]      din_b,
    output reg  [WIDTH-1:0]      dout_b
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk_a) begin
        if (we_a) begin
            mem[addr_a] <= din_a;
            dout_a      <= din_a;
        end else begin
            dout_a <= mem[addr_a];
        end
    end

    always @(posedge clk_b) begin
        if (we_b) begin
            mem[addr_b] <= din_b;
            dout_b      <= din_b;
        end else begin
            dout_b <= mem[addr_b];
        end
    end

endmodule
