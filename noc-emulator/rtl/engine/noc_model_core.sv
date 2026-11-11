module noc_model_core #(
    parameter int unsigned ROWS = 2,
    parameter int unsigned COLS = 2,
    parameter int unsigned VC_NUM = 2,
    parameter int unsigned BUFFER_DEPTH = 8,
    parameter int unsigned ENDPOINTS = ROWS * COLS,
    parameter int unsigned ENDPOINT_BITS = (ENDPOINTS <= 2) ? 1 : $clog2(ENDPOINTS),
    parameter int unsigned TAG_WIDTH = 12,
    parameter int unsigned LEN_BITS = 32,
    parameter int unsigned INTERNAL_LINKS = 2 * (ROWS * (COLS - 1) + (ROWS - 1) * COLS),
    parameter int unsigned LINK_COUNT = 2 * ENDPOINTS + INTERNAL_LINKS,
    parameter int unsigned STATS_COUNTER_BITS = 32,
    parameter logic [STATS_COUNTER_BITS-1:0] STATS_EPOCH_THRESHOLD =
        {STATS_COUNTER_BITS{1'b1}} -
        STATS_COUNTER_BITS'((STATS_COUNTER_BITS > 16) ? 32'd65535 : 1)
) (
    input  logic                                        clk,
    input  logic                                        rst_n,
    input  logic                                        model_step,
    output logic                                        step_ready,
    input  logic                                        valiant,
    input  logic                                        jump_valid,
    input  logic [63:0]                                 jump_cycle,
    input  logic [ENDPOINTS-1:0]                        event_valid,
    output logic [ENDPOINTS-1:0]                        event_ready,
    input  logic [ENDPOINTS-1:0][TAG_WIDTH-1:0]         event_tag,
    input  logic [ENDPOINTS-1:0][ENDPOINT_BITS-1:0]     event_dst,
    input  logic [ENDPOINTS-1:0][ENDPOINT_BITS-1:0]     event_mid,
    input  logic [ENDPOINTS-1:0][LEN_BITS-1:0]          event_flit_num,
    output logic [ENDPOINTS-1:0]                        completion_valid,
    input  logic [ENDPOINTS-1:0]                        completion_ready,
    output logic [ENDPOINTS-1:0][TAG_WIDTH-1:0]         completion_tag,
    output logic [63:0]                                 completion_cycle,
    output logic [63:0]                                 logical_cycle,
    output logic                                        network_idle,
    input  logic                                        clear_stats_epoch,
    output logic                                        stats_epoch_needed,
    output logic                                        stats_pipeline_idle,
    output logic [LINK_COUNT-1:0][STATS_COUNTER_BITS-1:0] stat_flits,
    output logic [LINK_COUNT-1:0][STATS_COUNTER_BITS-1:0] stat_heads,
    output logic [LINK_COUNT-1:0][STATS_COUNTER_BITS-1:0] stat_blocked,
    output logic [LINK_COUNT-1:0][STATS_COUNTER_BITS-1:0] stat_contended
);
    logic [LINK_COUNT-1:0] transfer_event;
    logic [LINK_COUNT-1:0] head_event;
    logic [LINK_COUNT-1:0] blocked_event;
    logic [LINK_COUNT-1:0] contended_event;
    logic [1:0] preparation_cycles;
    logic [ENDPOINTS-1:0] completion_ready_seen;

    // Route lookup and arbitration run in physical cycles while logical time
    // and all architectural mesh state remain frozen.
    assign step_ready = preparation_cycles == 3 && completion_ready == completion_ready_seen;
    always_ff @(posedge clk) begin
        if (!rst_n || model_step) preparation_cycles <= '0;
        else if (preparation_cycles != 3) preparation_cycles <= preparation_cycles + 1'b1;
        // A collector can change backpressure even while logical time is held.
        // Do not commit until the last preparation stage has observed it.
        if (!rst_n) completion_ready_seen <= '0;
        else completion_ready_seen <= completion_ready;
    end

    noc_mesh #(
        .ROWS(ROWS), .COLS(COLS), .VC_NUM(VC_NUM), .BUFFER_DEPTH(BUFFER_DEPTH),
        .TAG_WIDTH(TAG_WIDTH), .ENDPOINT_BITS(ENDPOINT_BITS), .LEN_BITS(LEN_BITS)
    ) mesh (
        .clk, .rst_n, .model_step, .valiant,
        .event_valid, .event_ready, .event_tag, .event_dst, .event_mid, .event_flit_num,
        .completion_valid, .completion_ready, .completion_tag,
        .stat_transfer(transfer_event), .stat_packet_head(head_event),
        .stat_no_credit(blocked_event), .stat_contended(contended_event),
        .network_idle
    );

    link_stats_bank #(
        .LINK_COUNT(LINK_COUNT), .COUNTER_BITS(STATS_COUNTER_BITS),
        .EPOCH_THRESHOLD(STATS_EPOCH_THRESHOLD)
    ) statistics (
        .clk, .rst_n, .model_step, .clear_epoch(clear_stats_epoch),
        .transfer(transfer_event), .packet_head(head_event),
        .no_credit(blocked_event), .contended(contended_event),
        .epoch_needed(stats_epoch_needed), .pipeline_idle(stats_pipeline_idle),
        .flit_count(stat_flits), .head_count(stat_heads),
        .blocked_count(stat_blocked), .contended_count(stat_contended)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            logical_cycle <= '0;
            completion_cycle <= 64'd1;
        end else if (model_step) begin
            if (jump_valid && jump_cycle > logical_cycle) begin
                logical_cycle <= jump_cycle;
                completion_cycle <= jump_cycle + 1'b1;
            end else begin
                logical_cycle <= completion_cycle;
                completion_cycle <= completion_cycle + 1'b1;
            end
        end
    end

endmodule
