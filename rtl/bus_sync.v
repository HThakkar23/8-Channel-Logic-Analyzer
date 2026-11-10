`timescale 1ns / 1ps
//
// Double flop synchronizer for carrying window_base into the pixel clock
// domain. A multi-bit bus crossed this way can briefly show a torn value
// if the bits do not all settle on the same edge; here the only cost is
// one visually wrong video frame right after a capture finishes, which
// self-corrects the next frame, so it is not worth a slower handshake.
//
module bus_sync #(
    parameter integer WIDTH = 12
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] async_in,
    output reg  [WIDTH-1:0] synced_out
);

    reg [WIDTH-1:0] stage0;

    always @(posedge clk) begin
        stage0     <= async_in;
        synced_out <= stage0;
    end

endmodule
