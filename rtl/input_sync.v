`timescale 1ns / 1ps
//
// Two flop synchronizer for the 8 probe inputs, which come from whatever
// is being probed with no timing relationship to our clock. A plain
// double flop chain is enough here since we only need a stable level,
// not the glitch rejection uart_rx.v needs on its single serial line.
//
module input_sync #(
    parameter integer WIDTH = 8
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
