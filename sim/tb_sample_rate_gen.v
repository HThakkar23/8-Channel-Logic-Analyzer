`timescale 1ns / 1ps
//
// Checks that sample_rate_gen produces one tick every `divider` cycles
// for a normal divider, and ticks every single cycle for the divider = 0
// and divider = 1 edge cases, which are the two values that would cause
// trouble for a naive "count down to zero" divider.
//
module tb_sample_rate_gen;

    reg        clk;
    reg        rst;
    reg [15:0] divider;
    wire       sample_tick;

    integer errors;
    integer i;
    integer gap;

    sample_rate_gen dut (
        .clk(clk),
        .rst(rst),
        .divider(divider),
        .sample_tick(sample_tick)
    );

    always #5 clk = ~clk; // 100 MHz

    task check_divider(input [15:0] test_divider, input [15:0] expected_gap);
        begin
            divider = test_divider;
            rst     = 1'b1;
            @(posedge clk); @(posedge clk);
            rst = 1'b0;

            // skip to the first tick
            while (!sample_tick) @(posedge clk);
            @(posedge clk);

            // measure the gap to the next two ticks
            for (i = 0; i < 2; i = i + 1) begin
                gap = 0;
                while (!sample_tick) begin
                    @(posedge clk);
                    gap = gap + 1;
                end
                if (gap !== expected_gap) begin
                    $display("FAIL: divider=%0d expected gap %0d, got %0d", test_divider, expected_gap, gap);
                    errors = errors + 1;
                end
                @(posedge clk);
            end
        end
    endtask

    initial begin
        clk     = 1'b0;
        rst     = 1'b1;
        divider = 16'd0;
        errors  = 0;

        check_divider(16'd0, 16'd1);   // divider 0 means every cycle
        check_divider(16'd1, 16'd1);   // divider 1 also means every cycle
        check_divider(16'd4, 16'd4);
        check_divider(16'd1000, 16'd1000);

        if (errors == 0)
            $display("PASS: tb_sample_rate_gen");
        else
            $display("FAIL: tb_sample_rate_gen, %0d error(s)", errors);

        $finish;
    end

endmodule
