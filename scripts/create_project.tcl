# Builds the Vivado project for the logic analyzer from scratch.
#
# Run this from the Vivado Tcl console with the project root as the
# current directory, for example:
#
#   cd C:/Users/hthakkar/Desktop/Hardware/logic-analyzer
#   source scripts/create_project.tcl
#
# This creates the project, adds every RTL file and testbench, adds the
# pin constraints, and generates the Clocking Wizard IP used for the
# 100 MHz system clock and the 25 MHz pixel clock. It stops short of
# running synthesis, implementation or bitstream generation so you can
# look over the project in the GUI first; the commands to run the rest
# of the flow in batch mode are at the bottom, commented out.

set proj_name "logic_analyzer"
set proj_dir  "./build"
set part_name "xc7z007s-1clg400c-1"

create_project $proj_name $proj_dir -part $part_name -force

set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

# RTL sources
add_files -norecurse {
    rtl/reset_sync.v
    rtl/baud_tick_gen.v
    rtl/uart_rx.v
    rtl/uart_tx.v
    rtl/input_sync.v
    rtl/bus_sync.v
    rtl/sample_rate_gen.v
    rtl/capture_buffer.v
    rtl/capture_engine.v
    rtl/cmd_protocol.v
    rtl/vga_timing.v
    rtl/waveform_renderer.v
    rtl/led_display.v
    rtl/logic_analyzer_top.v
}

# Testbenches, simulation only
add_files -fileset sim_1 -norecurse {
    sim/tb_sample_rate_gen.v
    sim/tb_capture_engine.v
    sim/tb_cmd_protocol.v
}

# Constraints
add_files -fileset constrs_1 -norecurse constr/blackboard_la.xdc

set_property top logic_analyzer_top [current_fileset]

# Clocking Wizard: one 100 MHz input becomes clk_sys at 100 MHz
# (effectively a buffered passthrough) and clk_pix at 25 MHz for the VGA
# side of the design, same arrangement as the uart-vga-terminal project.
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0

set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
    CONFIG.CLK_OUT1_PORT {clk_out1} \
    CONFIG.CLK_OUT2_PORT {clk_out2} \
] [get_ips clk_wiz_0]

generate_target all [get_ips clk_wiz_0]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $proj_dir. Open $proj_dir/$proj_name.xpr in Vivado,"
puts "or keep working from this Tcl console."

# --- Optional: full batch build ---
# Uncomment these lines to run synthesis, implementation and bitstream
# generation without opening the GUI at all.
#
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1
# puts "Bitstream at $proj_dir/$proj_name.runs/impl_1/logic_analyzer_top.bit"
