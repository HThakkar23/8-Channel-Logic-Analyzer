`timescale 1ns / 1ps
//
// Exercises cmd_protocol at its data level interface, driving rx_data and
// rx_valid directly instead of re-simulating UART bit timing, since
// uart_rx and uart_tx are already proven reused modules with their own
// testbenches in the uart-vga-terminal project. tx_busy is tied low here,
// standing in for a transmitter that is never actually busy, so every
// reply comes back as soon as cmd_protocol asks for it.
//
// capture_buffer is not instantiated either. dump_rdata is tied straight
// to dump_addr (zero extended), which turns the dump test into a simple
// check that cmd_protocol asks for the right DEPTH addresses in the right
// order and wraps them with the ring, without needing a real memory
// behind it.
//
module tb_cmd_protocol;

    localparam ADDR_W = 3;
    localparam DEPTH  = 8;

    reg clk;
    reg rst;

    reg  [7:0] rx_data;
    reg        rx_valid;
    wire [7:0] tx_data;
    wire       tx_start;
    reg        tx_busy;

    wire        arm_strobe;
    wire [15:0] divider;
    wire [2:0]  trig_channel;
    wire [1:0]  trig_mode;
    reg         armed, triggered, done;
    reg  [ADDR_W-1:0] window_base;

    wire               dump_active;
    wire [ADDR_W-1:0]  dump_addr;
    wire [7:0]         dump_rdata;

    integer errors;
    integer arm_pulse_count;
    integer timeout;
    integer i;
    reg [7:0] got;
    reg [7:0] expected;

    cmd_protocol #(
        .ADDR_W(ADDR_W),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy),
        .arm_strobe(arm_strobe),
        .divider(divider),
        .trig_channel(trig_channel),
        .trig_mode(trig_mode),
        .armed(armed),
        .triggered(triggered),
        .done(done),
        .window_base(window_base),
        .dump_active(dump_active),
        .dump_addr(dump_addr),
        .dump_rdata(dump_rdata)
    );

    assign dump_rdata = {{(8-ADDR_W){1'b0}}, dump_addr};

    always #5 clk = ~clk; // 100 MHz

    // counts how many cycles arm_strobe is high, used to check it is a
    // single cycle pulse rather than something left stuck on. sampled at
    // negedge, well after the posedge where the DUT's nonblocking
    // assignment to arm_strobe actually takes effect
    always @(negedge clk) begin
        if (arm_strobe)
            arm_pulse_count = arm_pulse_count + 1;
    end

    task send_byte(input [7:0] b);
        begin
            @(negedge clk);
            rx_data  = b;
            rx_valid = 1'b1;
            @(negedge clk);
            rx_valid = 1'b0;
        end
    endtask

    // waits for the single cycle tx_start pulse and captures tx_data
    // alongside it, sampling at negedge so the DUT's nonblocking updates
    // have already settled. checks tx_start right away before waiting,
    // since an unrecognized opcode replies with NACK one cycle sooner
    // than every other opcode (it never passes through ST_APPLY), and a
    // task that always waited for the next negedge first would walk
    // straight past that earlier pulse. once the pulse is found, it
    // steps one more negedge past it before returning, so a dump loop
    // calling this back to back never sees the same already consumed
    // pulse twice.
    task wait_tx(output [7:0] got_byte);
        begin
            timeout = 0;
            while (!tx_start && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            got_byte = tx_data;
            @(negedge clk);
        end
    endtask

    initial begin
        clk             = 1'b0;
        rst             = 1'b1;
        rx_data         = 8'd0;
        rx_valid        = 1'b0;
        tx_busy         = 1'b0;
        armed           = 1'b0;
        triggered       = 1'b0;
        done            = 1'b0;
        window_base     = {ADDR_W{1'b0}};
        errors          = 0;
        arm_pulse_count = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // ---------------------------------------------------------
        // ARM: expect ACK and exactly one cycle of arm_strobe
        // ---------------------------------------------------------
        send_byte(8'h01); // OP_ARM
        wait_tx(got);
        if (got !== 8'hAA) begin
            $display("FAIL: ARM reply = %02h, expected ACK", got);
            errors = errors + 1;
        end
        if (arm_pulse_count !== 1) begin
            $display("FAIL: arm_strobe pulsed %0d time(s), expected 1", arm_pulse_count);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // SET_DIVIDER: MSB byte first, expect divider == 16'h1234
        // ---------------------------------------------------------
        send_byte(8'h02); // OP_SET_DIVIDER
        send_byte(8'h12); // MSB
        send_byte(8'h34); // LSB
        wait_tx(got);
        if (got !== 8'hAA) begin
            $display("FAIL: SET_DIVIDER reply = %02h, expected ACK", got);
            errors = errors + 1;
        end
        if (divider !== 16'h1234) begin
            $display("FAIL: divider = %04h, expected 1234", divider);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // SET_TRIGGER: channel 5, mode 2 packed as [7:5][4:3]
        // ---------------------------------------------------------
        send_byte(8'h03); // OP_SET_TRIGGER
        send_byte({3'd5, 2'd2, 3'b000});
        wait_tx(got);
        if (got !== 8'hAA) begin
            $display("FAIL: SET_TRIGGER reply = %02h, expected ACK", got);
            errors = errors + 1;
        end
        if (trig_channel !== 3'd5) begin
            $display("FAIL: trig_channel = %0d, expected 5", trig_channel);
            errors = errors + 1;
        end
        if (trig_mode !== 2'd2) begin
            $display("FAIL: trig_mode = %0d, expected 2", trig_mode);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // STATUS: reply packs {5'b0, done, triggered, armed}
        // ---------------------------------------------------------
        armed     = 1'b1;
        triggered = 1'b0;
        done      = 1'b1;
        send_byte(8'h04); // OP_STATUS
        wait_tx(got);
        expected = {5'b0, done, triggered, armed};
        if (got !== expected) begin
            $display("FAIL: STATUS reply = %02h, expected %02h", got, expected);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // Unrecognized opcode: expect NACK
        // ---------------------------------------------------------
        send_byte(8'hFF);
        wait_tx(got);
        if (got !== 8'h00) begin
            $display("FAIL: bad opcode reply = %02h, expected NACK", got);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // DUMP: expect DEPTH bytes starting at window_base, wrapping
        // through the ring, one address per byte in order
        // ---------------------------------------------------------
        window_base = 3'd3;
        send_byte(8'h05); // OP_DUMP
        for (i = 0; i < DEPTH; i = i + 1) begin
            wait_tx(got);
            expected = {{(8-ADDR_W){1'b0}}, (window_base + i[ADDR_W-1:0])};
            if (got !== expected) begin
                $display("FAIL: dump byte %0d = %02h, expected %02h", i, got, expected);
                errors = errors + 1;
            end
        end
        @(negedge clk);
        if (dump_active !== 1'b0) begin
            $display("FAIL: dump_active still set after streaming %0d bytes", DEPTH);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_cmd_protocol");
        else
            $display("FAIL: tb_cmd_protocol, %0d error(s)", errors);

        $finish;
    end

endmodule
