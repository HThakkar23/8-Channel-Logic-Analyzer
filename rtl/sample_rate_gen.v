`timescale 1ns / 1ps
//
// Produces the sample_tick that clocks new probe data into the capture
// buffer. Unlike baud_tick_gen.v, divider here is set at runtime by the
// host over cmd_protocol.v, not fixed at build time.
//
// divider is a clock cycle count between ticks. 0 and 1 both mean "tick
// every cycle", so the divide never has to check for a zero divisor.
// cmd_protocol.v resets it to 1000 out of reset, a 100 kHz default.
// scripts/sample_rate_calc.py has the achievable rates for other values.
//
module sample_rate_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] divider,
    output reg         sample_tick
);

    reg [15:0] cnt;

    wire [15:0] effective_divider = (divider <= 16'd1) ? 16'd1 : divider;

    always @(posedge clk) begin
        if (rst) begin
            cnt         <= 16'd0;
            sample_tick <= 1'b0;
        end else if (cnt >= effective_divider - 1'b1) begin
            cnt         <= 16'd0;
            sample_tick <= 1'b1;
        end else begin
            cnt         <= cnt + 1'b1;
            sample_tick <= 1'b0;
        end
    end

endmodule
