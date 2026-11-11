set board_dir [file dirname [info script]]
set repo_root [file join $board_dir ../..]
set part_name xc7k480tffg1156-2
set control_address 0x00100000
set rtl_files [list \
    [file join $repo_root rtl noc noc_defs.svh] \
    [file join $repo_root rtl engine noc_emulator_protocol_pkg.sv] \
    [file join $repo_root rtl noc rr_arbiter.sv] \
    [file join $repo_root rtl noc vc_fifo.sv] \
    [file join $repo_root rtl noc noc_source_ni.sv] \
    [file join $repo_root rtl noc noc_router.sv] \
    [file join $repo_root rtl noc noc_mesh.sv] \
    [file join $repo_root rtl engine tag_pool.sv] \
    [file join $repo_root rtl engine link_stats_bank.sv] \
    [file join $repo_root rtl engine noc_model_core.sv] \
    [file join $repo_root rtl axi axi128_master.sv] \
    [file join $repo_root rtl engine noc_emulator_engine.sv] \
    [file join $board_dir noc_emulator_bd_wrapper.v]]

proc require_file {path} {
    if {![file isfile $path]} {
        error "Required file does not exist: $path"
    }
}

source [file join $repo_root config default.tcl]
if {$rows < 1 || $cols < 1 || $rows * $cols > 64} {
    error "Mesh must contain 1..64 nodes"
}
if {$vc_num ni {2 4}} { error "VC count must be 2 or 4" }
if {$buffer_depth ni {2 4 8 16}} { error "Buffer depth must be 2, 4, 8 or 16" }

proc require_one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected one $description, got [llength $objects]: $objects"
    }
    return [lindex $objects 0]
}

proc require_config {cell name value} {
    set property_name CONFIG.$name
    if {[lsearch -exact [list_property $cell] $property_name] < 0} {
        error "[get_property VLNV $cell] has no property $property_name"
    }
    set_property $property_name $value $cell
    set actual [get_property $property_name $cell]
    puts "INFO: [get_property NAME $cell] $property_name=$actual"
}

proc verify_config {cell name expected} {
    set property_name CONFIG.$name
    if {[lsearch -exact [list_property $cell] $property_name] < 0} {
        error "[get_property VLNV $cell] has no property $property_name"
    }
    set actual [get_property $property_name $cell]
    if {![string equal -nocase $actual $expected]} {
        error "[get_property NAME $cell] $property_name=$actual, expected $expected"
    }
    puts "INFO: [get_property NAME $cell] $property_name=$actual"
}

foreach path $rtl_files {
    require_file $path
}
