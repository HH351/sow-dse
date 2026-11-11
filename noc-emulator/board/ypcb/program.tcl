if {$argc != 1} {
    error "Usage: program.tcl <bitstream>"
}
set bitstream [lindex $argv 0]
if {![file isfile $bitstream]} {
    error "Bitstream does not exist: $bitstream"
}
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices xc7k480t_0]
if {[llength $devices] != 1} {
    error "Expected one xc7k480t_0 device, got: $devices"
}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
refresh_hw_device $device
close_hw_manager
puts "INFO: programmed $bitstream"
