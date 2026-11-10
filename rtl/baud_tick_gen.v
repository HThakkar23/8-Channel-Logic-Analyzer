`timescale 1ns / 1ps
//
// Free running divider that turns the system clock into a 16x oversample
// tick for the UART receiver. The divisor is computed at elaboration time
// from CLK_FREQ_HZ and BAUD_RATE, the same arithmetic scripts/sample_rate_calc.py
// uses for the host link numbers.
//
// At 100 MHz / 115200 baud this comes out to a divisor of 54, which lands
// the real bit rate about 0.47% off the nominal 115200, well inside what a
// standard 8N1 link tolerates. This is the same host UART link used in the
// uart-vga-terminal project, so the divisor and its error are unchanged.
//
// Reused unchanged from the uart-vga-terminal project.
//
module baud_tick_gen #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer OVERSAMPLE  = 16
) (
    input  wire clk,
    input  wire rst,
    output reg  tick_16x
);

    localparam integer DIVISOR   = CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNT_WIDTH = $clog2(DIVISOR);

    reg [CNT_WIDTH-1:0] div_cnt;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt  <= {CNT_WIDTH{1'b0}};
            tick_16x <= 1'b0;
        end else if (div_cnt == DIVISOR - 1) begin
            div_cnt  <= {CNT_WIDTH{1'b0}};
            tick_16x <= 1'b1;
        end else begin
            div_cnt  <= div_cnt + 1'b1;
            tick_16x <= 1'b0;
        end
    end

endmodule
