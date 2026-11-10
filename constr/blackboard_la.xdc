# Pin and timing constraints for the Real Digital Blackboard (Zynq-7000,
# XC7Z007S-1CLG400C).
#
# The clock, LED and PmodC pin letters below are taken from the Blackboard
# pin file published in lowRISC's ibex-demo-system project, which targets
# this exact board, so they are the verified ones rather than a guess.
# Everything else should still be checked against the master XDC on Real
# Digital's own resource page before building, since board revisions can
# differ. The probe header section below is the one piece this file does
# not have confirmed pin letters for; see the note there.

## Clock, 100 MHz board oscillator
set_property PACKAGE_PIN H16 [get_ports clk_ext]
set_property IOSTANDARD LVCMOS33 [get_ports clk_ext]
create_clock -period 10.000 -name clk_ext -waveform {0.000 5.000} [get_ports clk_ext]

## Reset button, BTN3 on the silkscreen
set_property PACKAGE_PIN M14 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

## LEDs, LD0 through LD9
set_property PACKAGE_PIN N20 [get_ports {led[0]}]
set_property PACKAGE_PIN P20 [get_ports {led[1]}]
set_property PACKAGE_PIN R19 [get_ports {led[2]}]
set_property PACKAGE_PIN T20 [get_ports {led[3]}]
set_property PACKAGE_PIN T19 [get_ports {led[4]}]
set_property PACKAGE_PIN U13 [get_ports {led[5]}]
set_property PACKAGE_PIN V20 [get_ports {led[6]}]
set_property PACKAGE_PIN W20 [get_ports {led[7]}]
set_property PACKAGE_PIN W19 [get_ports {led[8]}]
set_property PACKAGE_PIN Y19 [get_ports {led[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## UART on PMOD-C (JC), 115200 8N1
# JC2 is the board's transmit pin, JC3 is its receive pin. Plug a USB to
# TTL serial adapter into JC2 (board TX, goes to the adapter's RX) and JC3
# (board RX, from the adapter's TX), with a shared ground.
set_property PACKAGE_PIN W15 [get_ports uart_txd]
set_property PACKAGE_PIN V16 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]


# probe_in[0] through probe_in[5] land on the four free signal pins of
# the same PMOD-C header the UART uses (JC1, JC4, JC7 through JC10, minus
# the two pins already spoken for by uart_txd and uart_rxd above), plus
# the flow control pins JC1 and JC4 that this design leaves unused. That
# header only has eight signal pins total and two of them are the UART,
# so six is all PMOD-C has room for.
#
# probe_in[6] and probe_in[7] are left unconstrained here. Give them a
# PACKAGE_PIN on a free PMOD header (PMOD-A or PMOD-B) once you have
# confirmed the exact pin letters against your board's master XDC, or
# drop them and build with a 6 channel probe header by trimming
# trig_channel to 3'b101 and below and leaving those two bits of the
# dump unused.
set_property PACKAGE_PIN V15 [get_ports {probe_in[0]}]
set_property PACKAGE_PIN T16 [get_ports {probe_in[1]}]
set_property PACKAGE_PIN M19 [get_ports {probe_in[2]}]
set_property PACKAGE_PIN G14 [get_ports {probe_in[3]}]
set_property PACKAGE_PIN G17 [get_ports {probe_in[4]}]
set_property PACKAGE_PIN G15 [get_ports {probe_in[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {probe_in[*]}]

set_property PACKAGE_PIN Y17 [get_ports vga_hsync]
set_property PACKAGE_PIN Y18 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

set_property PACKAGE_PIN W18 [get_ports {vga_red[0]}]
set_property PACKAGE_PIN Y21 [get_ports {vga_red[1]}]
set_property PACKAGE_PIN Y22 [get_ports {vga_red[2]}]
set_property PACKAGE_PIN AA22 [get_ports {vga_red[3]}]

set_property PACKAGE_PIN Y14 [get_ports {vga_green[0]}]
set_property PACKAGE_PIN Y16 [get_ports {vga_green[1]}]
set_property PACKAGE_PIN AB22 [get_ports {vga_green[2]}]
set_property PACKAGE_PIN AA21 [get_ports {vga_green[3]}]

set_property PACKAGE_PIN AB21 [get_ports {vga_blue[0]}]
set_property PACKAGE_PIN AB20 [get_ports {vga_blue[1]}]
set_property PACKAGE_PIN AB19 [get_ports {vga_blue[2]}]
set_property PACKAGE_PIN AA19 [get_ports {vga_blue[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[*]}]

## Config options, standard for this part
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
