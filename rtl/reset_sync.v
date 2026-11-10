`timescale 1ns / 1ps
//
// Asynchronous assert, synchronous deassert reset bridge.
// Lets a single external reset source (a button, or configuration done)
// release cleanly inside one clock domain without landing on a clock edge
// at a random point and risking a metastable reset deassertion.
//
// Reused unchanged from the uart-vga-terminal project.
//
module reset_sync (
    input  wire clk,
    input  wire async_rst_in,   // active high, may change at any time
    output wire sync_rst_out    // active high, synchronous to clk
);

    reg [1:0] sync_ff;

    always @(posedge clk or posedge async_rst_in) begin
        if (async_rst_in)
            sync_ff <= 2'b11;
        else
            sync_ff <= {sync_ff[0], 1'b0};
    end

    assign sync_rst_out = sync_ff[1];

endmodule
