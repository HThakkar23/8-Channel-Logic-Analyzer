# Setup guide

This walks through building the project in Vivado and getting it running
on a Real Digital Blackboard. It assumes Vivado is already installed
(2019.2 or newer should work fine; this was written against the Zynq-7000
support in current Vivado releases) and that you have the board, a USB
to TTL serial adapter, something to probe with the 6 channel header, and
a monitor that can take VGA.

This project also ships a Python host script, `host/la_client.py`, that
talks to the board over the same serial link. It needs `pyserial`
installed on whatever machine you plug the board into, not on the
machine this was written on. Get that installed with
`pip install pyserial` before step 7 below.

## 1. Check the pin constraints first

Open `constr/blackboard_la.xdc`. The clock, reset button, LEDs and the
UART pins on PMOD header JC are taken from a published Blackboard pin
file and should be correct as is. Two blocks further down are marked
NEEDS VERIFICATION and need a look before you build:

- **Probe header.** `probe_in[0]` through `probe_in[5]` use the six free
  signal pins on PMOD header JC, the same header the UART uses. That
  header only has eight signal pins and two are already the UART, so six
  is all it has room for. `probe_in[6]` and `probe_in[7]` are left
  unconstrained. Either give them a pin on a free PMOD header once you
  have confirmed the letters against your board's master XDC, or build
  with only 6 probe channels by leaving those two bits of the dump
  unused and keeping trigger channel selection at 3'b101 and below.
- **VGA connector.** Some Blackboard revisions carry VGA through a small
  resistor ladder DAC; newer production boards may carry HDMI instead.
  There is also a specific flag in the file itself: `vga_red[0]` is
  assigned to pin W18, which a separate, verified pin reference for this
  board lists as an onboard RGB LED, not a VGA pin. Confirm this one
  against your board's master XDC before building, and move it if it
  turns out to collide.

If your board has no VGA connector, a VGA PMOD breakout board on any
free PMOD header works too, wired to the same `vga_hsync`, `vga_vsync`,
`vga_red`, `vga_green` and `vga_blue` ports in `logic_analyzer_top.v`.

## 2. Build the project

Open Vivado, go to the Tcl console, and run:

```
cd C:/Users/hthakkar/Desktop/Hardware/logic-analyzer
source scripts/create_project.tcl
```

This creates a project under `build/`, adds all the RTL files, the
testbenches, and the constraints file, and generates the Clocking Wizard
IP that produces the 100 MHz system clock and the 25 MHz pixel clock.
It stops before synthesis so you can look at the project first. The
bottom of the script has commented out lines that run synthesis,
implementation and bitstream generation in one go if you would rather
skip the GUI.

If you prefer to build everything by hand through the GUI instead of
running the script, the steps are:

1. File, New Project. Pick the Real Digital Blackboard board file if you
   have it installed, otherwise select part `xc7z007s-1clg400c-1` directly.
2. Add all files under `rtl/` as design sources.
3. Add the three files under `sim/` as simulation sources only.
4. Add `constr/blackboard_la.xdc` as a constraints source.
5. Open the IP catalog, find Clocking Wizard, and create one named
   `clk_wiz_0` with a 100 MHz input, output 1 at 100 MHz, output 2 at
   25 MHz, and both the locked signal and an active-high reset input
   enabled.
6. Set `logic_analyzer_top` as the top module.

## 3. Run the simulations (optional, needs a simulator)

This machine does not have a simulator installed, so the three
testbenches under `sim/` were written and checked by hand but never
actually run here. Once you have Vivado or another simulator available:

In Vivado, open the Simulation Sources fileset, right click on whichever
of `tb_sample_rate_gen`, `tb_capture_engine` or `tb_cmd_protocol` you want
to run, and set it as the simulation top, then run behavioral
simulation. Each testbench prints `PASS` or `FAIL` along with an error
count to the Tcl console.

With a standalone Icarus Verilog install instead, from the project root:

```
iverilog -o sim_rate.out rtl/sample_rate_gen.v sim/tb_sample_rate_gen.v
vvp sim_rate.out

iverilog -o sim_cap.out rtl/capture_buffer.v rtl/capture_engine.v sim/tb_capture_engine.v
vvp sim_cap.out

iverilog -o sim_cmd.out rtl/capture_buffer.v rtl/capture_engine.v rtl/sample_rate_gen.v rtl/cmd_protocol.v rtl/uart_rx.v rtl/uart_tx.v rtl/baud_tick_gen.v sim/tb_cmd_protocol.v
vvp sim_cmd.out
```

## 4. Synthesis, implementation, and the bitstream

From the Flow Navigator: Run Synthesis, then Run Implementation, then
Generate Bitstream. On this part, a clean build typically finishes in a
couple of minutes. The design uses one RAMB36 tile out of 50 for the
capture buffer (see the numbers in README.md) and a small fraction of
the available logic, so there is no concern about running out of
resources.

## 5. Program the board

Open Hardware Manager, connect to the board over JTAG, and program the
device with the generated `.bit` file. The heartbeat LED (`led[3]`)
blinking roughly once a second confirms the system clock is alive and
locked. The rest of the LEDs sit at their reset state, armed and
triggered and done all low, until a capture is started from the host.

## 6. Connect the probes

Wire up to 6 signals to `probe_in[0]` through `probe_in[5]` on PMOD
header JC, with a ground shared between the board and whatever you are
probing. Each probe input passes through its own two flop synchronizer
before capture, so there is no need to worry about exact timing
alignment between channels beyond ordinary signal integrity practice:
short leads, a shared ground, and nothing driving a probe pin outside
the board's 3.3 V logic levels.

## 7. Connect the host link and arm a capture

Wire a USB to TTL serial adapter to PMOD header JC: adapter TX to the
board's RX pin, adapter RX to the board's TX pin, and a shared ground
with the rest of the setup. With `pyserial` installed on the host
machine, run:

```
python host/la_client.py --port COM5 --rate 1000000 --channel 0 --mode rising
```

(use whatever serial port your adapter shows up as; on Linux or macOS
this looks like `/dev/ttyUSB0` instead of `COM5`). This arms the board
at a 1 Msa/s sample rate, waiting for a rising edge on probe channel 0.
Once the trigger fires and the post-trigger half of the buffer fills,
the script pulls the full 4096 sample capture back over the same link,
writes it to `capture.csv`, and prints a quick ASCII view of the first
few channels to the terminal. Run `python host/la_client.py --help` for
the full list of options, including picking a different trigger channel
or mode, a different sample rate, and which channels to show in the
ASCII view.

## 8. Watch it on the VGA monitor too

The same capture that `la_client.py` pulls down over the host link is
also drawn live on the VGA output as an 8 channel waveform, one sample
per pixel column, centered on the trigger point. No host software is
needed to see a capture this way; it updates the instant a capture
finishes and holds until the next one is armed.

## LED reference

| LED | Meaning |
|---|---|
| `led[0]` | armed, a capture is running and collecting the pre-trigger half |
| `led[1]` | triggered, the trigger condition has fired |
| `led[2]` | done, a full capture is sitting in the buffer, ready to dump |
| `led[3]` | heartbeat, toggles at roughly 1 Hz |
| `led[4]` | activity, toggles every sample tick, visibly speeds up or slows down with the sample rate |
| `led[7:5]` | the probe channel currently armed to trigger on, as a 3 bit number |
| `led[9:8]` | the trigger mode currently configured: 00 rising, 01 falling, 10 level high, 11 free run |

## Host command reference

| Opcode | Name | Payload | Reply |
|---|---|---|---|
| `0x01` | ARM | none | ACK or NACK |
| `0x02` | SET_DIVIDER | 2 bytes, sample rate divider, MSB first | ACK or NACK |
| `0x03` | SET_TRIGGER | 1 byte, channel in bits 7:5, mode in bits 4:3 | ACK or NACK |
| `0x04` | STATUS | none | 1 byte, bit 0 armed, bit 1 triggered, bit 2 done |
| `0x05` | DUMP | none | 4096 raw bytes, no framing |
