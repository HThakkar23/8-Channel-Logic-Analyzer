`timescale 1ns / 1ps
//
// Top level wiring for the logic analyzer. Two clock domains: a 100 MHz
// system domain runs the UART link, the host command parser, the sample
// rate divider and the capture FSM, and a 25 MHz pixel domain runs the
// VGA timing and the waveform renderer. The Clocking Wizard IP (reused
// from the uart-vga-terminal project) generates both from the board
// oscillator.
//
// capture_buffer's port A is shared between two system domain clients
// that never need it at the same time in normal operation: capture_engine
// writes samples in while a capture is running, and cmd_protocol reads
// them back out once the host asks for a dump. A plain priority mux
// picks between them. Port B belongs entirely to the pixel domain
// renderer, which only ever reads.
//
// window_base is the one value that actually has to cross between the
// two domains, since the renderer needs to know where the most recent
// capture starts. bus_sync carries it across; see that file for why a
// simple double flop synchronizer is the right tool here instead of the
// toggle based crossing used in the other project.
//
module logic_analyzer_top (
    input  wire        clk_ext,    // board oscillator, into the Clocking Wizard
    input  wire        btn_rst,    // async reset button, active high

    input  wire        uart_rxd,
    output wire         uart_txd,

    input  wire [7:0]  probe_in,   // 8 channel probe header, async to everything

    output wire [9:0]  led,

    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_red,
    output wire [3:0]  vga_green,
    output wire [3:0]  vga_blue
);

    // ---------------------------------------------------------------
    // Clocks and reset
    // ---------------------------------------------------------------
    wire clk_sys;   // 100 MHz
    wire clk_pix;   // 25 MHz
    wire clk_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk_ext),
        .resetn   (~btn_rst),
        .clk_out1 (clk_sys),
        .clk_out2 (clk_pix),
        .locked   (clk_locked)
    );

    wire rst_async = btn_rst || !clk_locked;

    wire rst_sys, rst_pix;
    reset_sync u_rst_sys (.clk(clk_sys), .async_rst_in(rst_async), .sync_rst_out(rst_sys));
    reset_sync u_rst_pix (.clk(clk_pix), .async_rst_in(rst_async), .sync_rst_out(rst_pix));

    // ---------------------------------------------------------------
    // Host UART link, 115200 8N1
    // ---------------------------------------------------------------
    wire tick_16x;
    baud_tick_gen u_baud (.clk(clk_sys), .rst(rst_sys), .tick_16x(tick_16x));

    wire [7:0] host_rx_data;
    wire       host_rx_valid;
    wire       host_rx_frame_err;
    uart_rx u_uart_rx (
        .clk(clk_sys), .rst(rst_sys), .tick_16x(tick_16x), .rx_pin(uart_rxd),
        .rx_data(host_rx_data), .rx_valid(host_rx_valid), .rx_frame_err(host_rx_frame_err)
    );

    wire [7:0] host_tx_data;
    wire       host_tx_start;
    wire       host_tx_busy;
    uart_tx u_uart_tx (
        .clk(clk_sys), .rst(rst_sys),
        .tx_start(host_tx_start), .tx_data(host_tx_data),
        .tx_pin(uart_txd), .tx_busy(host_tx_busy)
    );

    // ---------------------------------------------------------------
    // Probe inputs
    // ---------------------------------------------------------------
    wire [7:0] probe_synced;
    input_sync #(.WIDTH(8)) u_probe_sync (
        .clk(clk_sys), .async_in(probe_in), .synced_out(probe_synced)
    );

    // ---------------------------------------------------------------
    // Sample rate, capture engine, host command parser
    // ---------------------------------------------------------------
    wire [15:0] divider;
    wire        sample_tick;
    sample_rate_gen u_rate (
        .clk(clk_sys), .rst(rst_sys), .divider(divider), .sample_tick(sample_tick)
    );

    wire        arm_strobe;
    wire [2:0]  trig_channel;
    wire [1:0]  trig_mode;
    wire        armed, triggered, done;
    wire [11:0] window_base;
    wire        capture_we;
    wire [11:0] capture_addr;
    wire [7:0]  capture_din;

    capture_engine u_capture (
        .clk(clk_sys), .rst(rst_sys),
        .sample_tick(sample_tick), .probe_in(probe_synced),
        .arm_strobe(arm_strobe), .trig_channel(trig_channel), .trig_mode(trig_mode),
        .capture_we(capture_we), .capture_addr(capture_addr), .capture_din(capture_din),
        .armed(armed), .triggered(triggered), .done(done), .window_base(window_base)
    );

    wire        dump_active;
    wire [11:0] dump_addr;
    wire [7:0]  dump_rdata;

    cmd_protocol u_cmd (
        .clk(clk_sys), .rst(rst_sys),
        .rx_data(host_rx_data), .rx_valid(host_rx_valid),
        .tx_data(host_tx_data), .tx_start(host_tx_start), .tx_busy(host_tx_busy),
        .arm_strobe(arm_strobe), .divider(divider),
        .trig_channel(trig_channel), .trig_mode(trig_mode),
        .armed(armed), .triggered(triggered), .done(done), .window_base(window_base),
        .dump_active(dump_active), .dump_addr(dump_addr), .dump_rdata(dump_rdata)
    );

    // capture writes and dump reads never need port A at the same time in
    // normal use, dump wins the mux since the host only dumps once done is set
    wire        bufA_we   = dump_active ? 1'b0       : capture_we;
    wire [11:0] bufA_addr = dump_active ? dump_addr  : capture_addr;
    wire [7:0]  bufA_dout;
    assign dump_rdata = bufA_dout;

    // ---------------------------------------------------------------
    // VGA timing and waveform renderer, pixel clock domain
    // ---------------------------------------------------------------
    wire [11:0] window_base_pix;
    bus_sync #(.WIDTH(12)) u_bus_sync (
        .clk(clk_pix), .async_in(window_base), .synced_out(window_base_pix)
    );

    wire        hsync_raw, vsync_raw, active_raw;
    wire [9:0]  pixel_x, pixel_y;
    wire        frame_tick;
    vga_timing u_vga_timing (
        .clk_pix(clk_pix), .rst(rst_pix),
        .hsync(hsync_raw), .vsync(vsync_raw), .active(active_raw),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .frame_tick(frame_tick)
    );

    wire [11:0] render_addr;
    wire [7:0]  render_rdata;
    wire [9:0]  pixel_x_d, pixel_y_d;
    wire        active_d;
    wire        trace_on, marker_on;

    waveform_renderer u_renderer (
        .clk_pix(clk_pix), .rst_pix(rst_pix),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .active(active_raw),
        .window_base_pix(window_base_pix),
        .render_addr(render_addr), .render_rdata(render_rdata),
        .pixel_x_d(pixel_x_d), .pixel_y_d(pixel_y_d), .active_d(active_d),
        .trace_on(trace_on), .marker_on(marker_on)
    );

    capture_buffer u_capture_buffer (
        .clk_a(clk_sys), .clk_b(clk_pix),
        .we_a(bufA_we), .addr_a(bufA_addr), .din_a(capture_din), .dout_a(bufA_dout),
        .we_b(1'b0), .addr_b(render_addr), .din_b(8'd0), .dout_b(render_rdata)
    );

    // hsync/vsync need the same one cycle delay as pixel_x_d/pixel_y_d so
    // they still line up with the trace/marker pixel they were issued for
    reg hsync_d, vsync_d;
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            hsync_d <= 1'b1;
            vsync_d <= 1'b1;
        end else begin
            hsync_d <= hsync_raw;
            vsync_d <= vsync_raw;
        end
    end

    assign vga_hsync = hsync_d;
    assign vga_vsync = vsync_d;

    assign vga_red   = trace_on ? 4'hF : (marker_on ? 4'hF : 4'h0);
    assign vga_green = trace_on ? 4'hF : 4'h0;
    assign vga_blue  = trace_on ? 4'hF : 4'h0;

    // ---------------------------------------------------------------
    // Front panel LEDs
    // ---------------------------------------------------------------
    led_display u_led (
        .clk(clk_sys), .rst(rst_sys),
        .armed(armed), .triggered(triggered), .done(done),
        .sample_tick(sample_tick),
        .trig_channel(trig_channel), .trig_mode(trig_mode),
        .led(led)
    );

endmodule
