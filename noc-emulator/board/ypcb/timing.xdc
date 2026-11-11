# memory_ready is asynchronous to the 100 MHz model clock. Only the first
# ASYNC_REG stage is excluded; the second stage remains normally timed.
set memory_ready_stage0 [get_pins -quiet -hierarchical -regexp \
    {.*memory_ready_sync_reg\[0\]/D}]
set_false_path -to $memory_ready_stage0
