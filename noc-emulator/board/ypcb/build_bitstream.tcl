if {$argc > 1} {
    error "Usage: build_bitstream.tcl ?jobs?"
}
set jobs 16
if {$argc == 1} { set jobs [lindex $argv 0] }
if {![string is integer -strict $jobs] || $jobs < 1} { error "jobs must be positive" }

source [file join [file dirname [info script]] common.tcl]
set build_dir [file join $repo_root build board]
set project_dir [file join $build_dir project]
set mig_prj [file join $board_dir mig_a.prj]
set board_xdc [file join $board_dir IO_Port.xdc]
set timing_xdc [file join $board_dir timing.xdc]
require_file $mig_prj
require_file $board_xdc
require_file $timing_xdc
file mkdir $build_dir

create_project -force noc_emulator $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse $rtl_files
set_property include_dirs [list [file join $repo_root rtl noc]] [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse $board_xdc
add_files -fileset constrs_1 -norecurse $timing_xdc
set_property PROCESSING_ORDER LATE [get_files $timing_xdc]
update_compile_order -fileset sources_1

create_bd_design top

set xdma [create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.2 xdma_0]
# XC7K480T board PCIe / XDMA configuration.
set xdma_config [list \
    mode_selection Basic \
    axi_data_width 128_bit \
    axisten_freq 250 \
    pl_link_cap_max_link_speed 5.0_GT/s \
    pl_link_cap_max_link_width X8 \
    xdma_axi_intf_mm AXI_Memory_Mapped \
    xdma_rnum_chnl 2 \
    xdma_wnum_chnl 2 \
    xdma_axilite_slave false \
    cfg_mgmt_if true \
    pcie_id_if FALSE \
    en_axi_slave_if true \
    pf0_bar0_enabled true \
    pf0_bar0_64bit false \
    pf0_bar0_prefetchable false \
    pf0_bar0_type Memory \
    pf0_bar0_scale Kilobytes \
    pf0_bar0_size 128 \
    vendor_id 10EE \
    pf0_device_id 7028 \
    pf0_revision_id 00 \
    pf0_subsystem_vendor_id 10EE \
    pf0_subsystem_id 0007 \
    pf0_class_code 070001 \
    pcie_blk_locn X0Y0 \
    ref_clk_freq 100_MHz \
    select_quad GTH_Quad_128 \
    plltype QPLL1 \
    lane_order Bottom \
    enable_lane_reversal false \
    sys_reset_polarity ACTIVE_LOW]
set xdma_properties {}
foreach {name value} $xdma_config {
    set property_name CONFIG.$name
    if {[lsearch -exact [list_property $xdma] $property_name] < 0} {
        error "[get_property VLNV $xdma] has no property $property_name"
    }
    lappend xdma_properties $property_name $value
}
set_property -dict $xdma_properties $xdma
verify_config $xdma functional_mode DMA
foreach {name value} $xdma_config {
    verify_config $xdma $name $value
}

set mig [create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_7series_0]
require_config $mig BOARD_MIG_PARAM Custom
require_config $mig MIG_DONT_TOUCH_PARAM Custom
require_config $mig RESET_BOARD_INTERFACE Custom
require_config $mig XML_INPUT_FILE $mig_prj

set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
require_config $smc NUM_SI 2
require_config $smc NUM_MI 4
require_config $smc NUM_CLKS 3
# Pipeline both sides of the switchboards; retain the default entry/exit slices.
require_config $smc ADVANCED_PROPERTIES {__view__ {timing {SW0 {AR_S_PIPE 1 AW_S_PIPE 1 W_S_PIPE 1 R_S_PIPE 1 B_S_PIPE 1}}}}

# Keep the 128-to-512-bit upsizer out of the PCIe 250 MHz clock domain.
# Dedicated asynchronous FIFOs cross the narrow bus into the DDR UI domain.
set host_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 host_axi_slice]
# Vivado 2025.2 uses Light (7) for single-beat address/response channels
# and Full (1) for burst data channels; both directions are registered.
foreach channel {AW AR B} { require_config $host_slice REG_$channel 7 }
foreach channel {W R} { require_config $host_slice REG_$channel 1 }
set host_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 host_axi_cdc]
require_config $host_cdc ACLK_ASYNC 1
require_config $host_cdc SYNCHRONIZATION_STAGES 3

set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
    require_config $clk_wiz PRIM_IN_FREQ 50.000
require_config $clk_wiz CLKOUT1_REQUESTED_OUT_FREQ 100.000
require_config $clk_wiz RESET_TYPE ACTIVE_LOW
require_config $clk_wiz RESET_PORT resetn
require_config $clk_wiz USE_RESET true
require_config $clk_wiz USE_LOCKED true

set pcie_buf [create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf]
require_config $pcie_buf C_BUF_TYPE IBUFDSGTE
set rst_model [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_model_100M]
set rst_c0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_mig_c0]
set rst_c1 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_mig_c1]
set calib_and [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 calib_and]
require_config $calib_and C_OPERATION and
require_config $calib_and C_SIZE 1

set engine [create_bd_cell -type module -reference noc_emulator_bd_wrapper noc_emulator_0]
set_property -dict [list \
    CONFIG.ROWS $rows \
    CONFIG.COLS $cols \
    CONFIG.VC_NUM $vc_num \
    CONFIG.BUFFER_DEPTH $buffer_depth \
    CONFIG.STATS_COUNTER_BITS $stats_counter_bits \
    CONFIG.CONTROL_ADDR $control_address] $engine

connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI] [get_bd_intf_pins host_axi_slice/S_AXI]
connect_bd_intf_net [get_bd_intf_pins host_axi_slice/M_AXI] [get_bd_intf_pins host_axi_cdc/S_AXI]
connect_bd_intf_net [get_bd_intf_pins host_axi_cdc/M_AXI] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins noc_emulator_0/M_AXI] [get_bd_intf_pins axi_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins mig_7series_0/S0_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M01_AXI] [get_bd_intf_pins mig_7series_0/S1_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M02_AXI] [get_bd_intf_pins mig_7series_0/S0_AXI_CTRL]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M03_AXI] [get_bd_intf_pins mig_7series_0/S1_AXI_CTRL]

connect_bd_net [get_bd_pins util_ds_buf/IBUF_OUT] [get_bd_pins xdma_0/sys_clk]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins host_axi_slice/aclk] [get_bd_pins host_axi_cdc/s_axi_aclk]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins host_axi_slice/aresetn] [get_bd_pins host_axi_cdc/s_axi_aresetn]
connect_bd_net [get_bd_pins mig_7series_0/c0_ui_clk] [get_bd_pins axi_smc/aclk] \
    [get_bd_pins host_axi_cdc/m_axi_aclk] [get_bd_pins rst_mig_c0/slowest_sync_clk]
connect_bd_net [get_bd_pins mig_7series_0/c1_ui_clk] [get_bd_pins axi_smc/aclk1] [get_bd_pins rst_mig_c1/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] [get_bd_pins axi_smc/aclk2] \
    [get_bd_pins noc_emulator_0/clk] [get_bd_pins rst_model_100M/slowest_sync_clk]

connect_bd_net [get_bd_pins mig_7series_0/c0_ui_clk_sync_rst] [get_bd_pins rst_mig_c0/ext_reset_in]
connect_bd_net [get_bd_pins mig_7series_0/c0_mmcm_locked] [get_bd_pins rst_mig_c0/dcm_locked]
connect_bd_net [get_bd_pins rst_mig_c0/peripheral_aresetn] \
    [get_bd_pins mig_7series_0/c0_aresetn] [get_bd_pins axi_smc/aresetn] [get_bd_pins host_axi_cdc/m_axi_aresetn]
connect_bd_net [get_bd_pins mig_7series_0/c1_ui_clk_sync_rst] [get_bd_pins rst_mig_c1/ext_reset_in]
connect_bd_net [get_bd_pins mig_7series_0/c1_mmcm_locked] [get_bd_pins rst_mig_c1/dcm_locked]
connect_bd_net [get_bd_pins rst_mig_c1/peripheral_aresetn] [get_bd_pins mig_7series_0/c1_aresetn]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst_model_100M/dcm_locked]
connect_bd_net [get_bd_pins rst_model_100M/peripheral_aresetn] [get_bd_pins noc_emulator_0/rst_n]
connect_bd_net [get_bd_pins mig_7series_0/c0_init_calib_complete] [get_bd_pins calib_and/Op1]
connect_bd_net [get_bd_pins mig_7series_0/c1_init_calib_complete] [get_bd_pins calib_and/Op2]
connect_bd_net [get_bd_pins calib_and/Res] [get_bd_pins noc_emulator_0/memory_ready]

set reset_port [create_bd_port -dir I -type rst reset_rtl_0]
set_property CONFIG.POLARITY ACTIVE_LOW $reset_port
connect_bd_net $reset_port [get_bd_pins xdma_0/sys_rst_n] [get_bd_pins mig_7series_0/sys_rst] \
    [get_bd_pins clk_wiz/resetn] [get_bd_pins rst_model_100M/ext_reset_in]
set model_clock [create_bd_port -dir I -type clk -freq_hz 50000000 clk_in1_0]
connect_bd_net $model_clock [get_bd_pins clk_wiz/clk_in1]

foreach {pin external_name} {
    xdma_0/pcie_mgt pcie_7x_mgt_rtl_0
    util_ds_buf/CLK_IN_D diff_clock_rtl_0
    mig_7series_0/C0_SYS_CLK C0_SYS_CLK_0
    mig_7series_0/C1_SYS_CLK C1_SYS_CLK_0
    mig_7series_0/C0_DDR3 C0_DDR3_0
    mig_7series_0/C1_DDR3 C1_DDR3_0
} {
    set pin_object [require_one [get_bd_intf_pins -quiet $pin] "interface pin $pin"]
    set before_ports [get_bd_intf_ports -quiet]
    make_bd_intf_pins_external $pin_object
    set created_ports {}
    foreach candidate [get_bd_intf_ports -quiet] {
        if {[lsearch -exact $before_ports $candidate] < 0} {
            lappend created_ports $candidate
        }
    }
    set external [require_one $created_ports "external interface for $pin"]
    if {[get_property NAME $external] ne $external_name} {
        set_property name $external_name $external
    }
}

set c0_segment [require_one [get_bd_addr_segs -quiet mig_7series_0/c0_memmap/c0_memaddr] "MIG C0 memory segment"]
set c1_segment [require_one [get_bd_addr_segs -quiet mig_7series_0/c1_memmap/c1_memaddr] "MIG C1 memory segment"]
set c0_ctrl_segment [require_one \
    [get_bd_addr_segs -quiet mig_7series_0/c0_s_axi_ctrl_memmap/c0_s_axi_ctrl_memaddr] \
    "MIG C0 control segment"]
set c1_ctrl_segment [require_one \
    [get_bd_addr_segs -quiet mig_7series_0/c1_s_axi_ctrl_memmap/c1_s_axi_ctrl_memaddr] \
    "MIG C1 control segment"]
foreach {space prefix} [list \
    [require_one [get_bd_addr_spaces -quiet xdma_0/M_AXI] "XDMA address space"] xdma \
    [require_one [get_bd_addr_spaces -quiet noc_emulator_0/M_AXI] "emulator address space"] emulator] {
    create_bd_addr_seg -range 2G -offset 0x00000000 $space $c0_segment SEG_${prefix}_ddr_c0
    create_bd_addr_seg -range 2G -offset 0x80000000 $space $c1_segment SEG_${prefix}_ddr_c1
    create_bd_addr_seg -range 1M -offset 0x100100000 $space $c0_ctrl_segment SEG_${prefix}_ctrl_c0
    create_bd_addr_seg -range 1M -offset 0x100200000 $space $c1_ctrl_segment SEG_${prefix}_ctrl_c1
}

regenerate_bd_layout
validate_bd_design
save_bd_design
generate_target all [get_files top.bd]
make_wrapper -files [get_files top.bd] -top -import
set_property top top_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
set_property strategy Flow_PerfOptimized_high $synth_run
set_property strategy Performance_Explore $impl_run
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
set status [get_property STATUS $impl_run]
puts "INFO: implementation status=$status"
if {![string match "*route_design Complete*" $status]} {
    error "Implementation failed before timing acceptance: $status"
}

open_run impl_1
set initial_setup_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {$initial_setup_path eq ""} {
    error "No setup timing path found after route_design"
}
set initial_wns [get_property SLACK $initial_setup_path]
puts "INFO: initial routed WNS=$initial_wns ns"
if {$initial_wns < 0.0} {
    puts "INFO: Running post-route physical optimization and TNS cleanup."
    phys_opt_design -directive AggressiveExplore
    route_design -tns_cleanup
}
report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $build_dir timing_summary.rpt]
report_route_status -file [file join $build_dir route_status.rpt]
report_drc -file [file join $build_dir drc.rpt]
set setup_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
set hold_path [lindex [get_timing_paths -delay_type min -max_paths 1] 0]
if {$setup_path eq "" || $hold_path eq ""} {
    error "No setup/hold timing paths found after route_design"
}
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
puts "INFO: routed timing WNS=$wns ns WHS=$whs ns"
if {$wns < 0.0 || $whs < 0.0} {
    error "Refusing to generate bitstream with failing timing: WNS=$wns WHS=$whs"
}

write_checkpoint -force [file join $build_dir noc_emulator_routed.dcp]
write_bitstream -force [file join $build_dir noc_emulator.bit]
puts "INFO: bitstream=[file join $build_dir noc_emulator.bit]"
