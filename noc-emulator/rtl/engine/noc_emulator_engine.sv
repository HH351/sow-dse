module noc_emulator_engine #(
    parameter int unsigned ROWS = 8,
    parameter int unsigned COLS = 8,
    parameter int unsigned VC_NUM = 2,
    parameter int unsigned BUFFER_DEPTH = 8,
    parameter int unsigned STATS_COUNTER_BITS = 32,
    parameter int unsigned ADDR_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH = 4,
    parameter logic [ADDR_WIDTH-1:0] CONTROL_ADDR = 64'h0010_0000,
    parameter logic [63:0] DDR_LIMIT = 64'h1_0000_0000,
    parameter int unsigned POLL_INTERVAL = 65536,
    parameter int unsigned ENDPOINTS = ROWS * COLS,
    parameter int unsigned ENDPOINT_BITS = (ENDPOINTS <= 2) ? 1 : $clog2(ENDPOINTS),
    parameter int unsigned INTERNAL_LINKS = 2 * (ROWS * (COLS - 1) + (ROWS - 1) * COLS),
    parameter int unsigned TAG_CAPACITY = ENDPOINTS * (
        5 * VC_NUM * BUFFER_DEPTH + VC_NUM + 2
    ) + INTERNAL_LINKS + 2,
    parameter int unsigned TAG_WIDTH = (TAG_CAPACITY <= 2) ? 1 : $clog2(TAG_CAPACITY),
    parameter int unsigned LINK_COUNT = 2 * ENDPOINTS + INTERNAL_LINKS,
    localparam int unsigned LINK_BITS = (LINK_COUNT <= 2) ? 1 : $clog2(LINK_COUNT)
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET rst_n, FREQ_HZ 100000000" *)
    input  logic                         clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
    input  logic                         rst_n,
    input  logic                         memory_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWID" *)
    output logic [AXI_ID_WIDTH-1:0]      m_axi_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output logic [ADDR_WIDTH-1:0]        m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output logic [7:0]                   m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output logic [2:0]                   m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output logic [1:0]                   m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
    output logic                         m_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
    output logic [3:0]                   m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
    output logic [2:0]                   m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
    output logic [3:0]                   m_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output logic                         m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  logic                         m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output logic [127:0]                 m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output logic [15:0]                  m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output logic                         m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output logic                         m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  logic                         m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BID" *)
    input  logic [AXI_ID_WIDTH-1:0]      m_axi_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  logic [1:0]                   m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  logic                         m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output logic                         m_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
    output logic [AXI_ID_WIDTH-1:0]      m_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    output logic [ADDR_WIDTH-1:0]        m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output logic [7:0]                   m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output logic [2:0]                   m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output logic [1:0]                   m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
    output logic                         m_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
    output logic [3:0]                   m_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
    output logic [2:0]                   m_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
    output logic [3:0]                   m_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output logic                         m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  logic                         m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
    input  logic [AXI_ID_WIDTH-1:0]      m_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  logic [127:0]                 m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  logic [1:0]                   m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  logic                         m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  logic                         m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 64, ID_WIDTH 4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, SUPPORTS_NARROW_BURST 0" *)
    output logic                         m_axi_rready
);
    import noc_emulator_protocol_pkg::*;
    localparam logic [63:0] EVENTS_BASE = CONTROL_ADDR + 4096;
    localparam int DESC_BEATS = (ENDPOINTS + 3) / 4;
    localparam int STAT_VALUES = 4 * LINK_COUNT;
    localparam int STAT_BITS = $clog2(STAT_VALUES);

    typedef enum logic [5:0] {
        S_BOOT_WAIT, S_BOOT_CLEAR, S_BOOT_STATUS,
        S_WAIT, S_POLL_CMD, S_POLL_DATA, S_CHECK, S_MARK_RUNNING, S_ACK,
        S_INIT_STATS, S_DESC_CMD, S_DESC_DATA, S_PARSE, S_START, S_RUN,
        S_FEED_META, S_FEED_CACHE, S_FEED_PROMOTE, S_FEED_CMD, S_FEED_DATA,
        S_COLLECT_READ, S_COLLECT_STORE, S_ACC_READ, S_ACC_ADD, S_ACC_CLEAR,
        S_EXPORT_READ, S_EXPORT_PACK, S_FLUSH, S_DONE, S_ERROR_CLEAR,
        S_ERROR_STATUS, S_FINISH, S_JUMP_SCAN, S_JUMP_APPLY,
        S_WRITE_CMD, S_WRITE_DATA, S_WRITE_RESPONSE
    } state_t;
    state_t main_state, after_write, flush_resume;
    (* ASYNC_REG = "TRUE" *) logic [1:0] memory_ready_sync;
    logic [31:0] poll_counter;
    logic [127:0] command_word;
    logic [31:0] event_count, completion_written;
    logic valiant;
    logic [15:0] error_code, command_error;
    logic [63:0] completion_base, stats_base, proposed_completion, proposed_stats;
    logic datapath_rst_n;

    logic rd_cmd_valid, rd_cmd_ready, rd_data_valid, rd_data_ready, rd_data_last;
    logic [ADDR_WIDTH-1:0] rd_cmd_addr;
    logic [4:0] rd_cmd_beats;
    logic [127:0] rd_data;
    logic rd_error, rd_error_rlast;
    logic [1:0] rd_error_resp;
    logic wr_cmd_valid, wr_cmd_ready, wr_data_valid, wr_data_ready;
    logic [ADDR_WIDTH-1:0] wr_cmd_addr;
    logic [4:0] wr_cmd_beats;
    logic [127:0] wr_data;
    logic [15:0] wr_data_strb;
    logic wr_done, wr_error;
    logic [1:0] wr_error_resp;
    logic [63:0] write_address;
    logic [4:0] write_beats, write_index, buffer_count;
    logic [127:0] write_buffer [0:15];
    logic completion_flush;

    logic [127:0] descriptor_words [0:DESC_BEATS-1];
    logic [3:0] descriptor_beat;
    logic [ENDPOINT_BITS-1:0] descriptor_index;
    logic [63:0] descriptor_sum;
    logic [31:0] descriptor_count;
    // Per source: previous-time-valid, previous time, remaining, next packet key.
    (* ram_style = "block" *) logic [128:0] source_state [0:ENDPOINTS-1];
    logic [128:0] source_meta;
    (* ram_style = "block" *) logic [127:0] event_cache [0:ENDPOINTS*16-1];
    logic [ENDPOINTS-1:0][4:0] cache_count;
    logic [ENDPOINTS-1:0][3:0] cache_position;
    logic [ENDPOINT_BITS-1:0] feeder_source;
    logic [4:0] fetch_beats;
    logic [3:0] fetch_index;
    logic [127:0] cached_event;
    logic feeder_invalid;

    logic [ENDPOINTS-1:0] head_valid, head_has_next, source_needs_head, source_active;
    logic [ENDPOINTS-1:0][63:0] head_send_time;
    logic [ENDPOINTS-1:0][ENDPOINT_BITS-1:0] head_dst, head_mid;
    logic [ENDPOINTS-1:0][31:0] head_flit_num;
    logic [ENDPOINTS-1:0][TAG_WIDTH-1:0] head_tag;
    logic [ENDPOINTS-1:0] event_valid, event_ready;
    logic tag_allocate, tag_allocate_ready, tag_release;
    logic [TAG_WIDTH-1:0] allocated_tag, released_tag;
    (* ram_style = "block" *) logic [31:0] context_table [0:TAG_CAPACITY-1];
    logic [31:0] context_read_key;
    logic [ENDPOINTS-1:0] completion_valid, completion_ready, completion_pending;
    logic [ENDPOINTS-1:0][TAG_WIDTH-1:0] completion_tag, completion_pending_tag;
    logic [ENDPOINT_BITS-1:0] completion_scan_index;
    logic [63:0] completion_wave_cycle, completion_cycle, logical_cycle;
    logic network_idle_raw, network_idle_sampled, model_step_previous, idle_confirmed;
    logic all_sources_known, all_sources_finished, idle_jump_needed, model_complete;
    logic model_step, jump_valid, core_step_ready;
    logic event_due_ready, run_permitted;
    logic [63:0] jump_cycle;
    logic [ENDPOINT_BITS-1:0] jump_index;

    logic stats_epoch_needed, stats_pipeline_idle, clear_stats_epoch, stats_final;
    logic [LINK_COUNT-1:0][STATS_COUNTER_BITS-1:0] stat_flits, stat_heads, stat_blocked, stat_contended;
    (* ram_style = "block" *) logic [63:0] stats_total [0:STAT_VALUES-1];
    logic [STAT_BITS-1:0] stats_index, export_index;
    logic [63:0] stats_read_value, export_low, stats_addend;
    logic [63:0] stats_write_address;

    function automatic logic [63:0] page_align(input logic [63:0] value);
        page_align = (value + 4095) & ~64'd4095;
    endfunction

    task automatic start_write(input logic [63:0] address,
        input logic [4:0] beats, input state_t resume_state);
        write_address <= address;
        write_beats <= beats;
        write_index <= '0;
        after_write <= resume_state;
        main_state <= S_WRITE_CMD;
    endtask
    axi128_master #(.ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(AXI_ID_WIDTH)) axi (
        .clk, .rst_n, .rd_cmd_valid, .rd_cmd_ready, .rd_cmd_addr, .rd_cmd_beats,
        .rd_data_valid, .rd_data_ready, .rd_data, .rd_data_last,
        .rd_error, .rd_error_rlast, .rd_error_resp,
        .wr_cmd_valid, .wr_cmd_ready, .wr_cmd_addr, .wr_cmd_beats,
        .wr_data_valid, .wr_data_ready, .wr_data, .wr_data_strb,
        .wr_done, .wr_error, .wr_error_resp,
        .m_axi_awid, .m_axi_awaddr, .m_axi_awlen, .m_axi_awsize, .m_axi_awburst,
        .m_axi_awlock, .m_axi_awcache, .m_axi_awprot, .m_axi_awqos,
        .m_axi_awvalid, .m_axi_awready, .m_axi_wdata, .m_axi_wstrb,
        .m_axi_wlast, .m_axi_wvalid, .m_axi_wready, .m_axi_bid, .m_axi_bresp,
        .m_axi_bvalid, .m_axi_bready, .m_axi_arid, .m_axi_araddr, .m_axi_arlen,
        .m_axi_arsize, .m_axi_arburst, .m_axi_arlock, .m_axi_arcache,
        .m_axi_arprot, .m_axi_arqos, .m_axi_arvalid, .m_axi_arready,
        .m_axi_rid, .m_axi_rdata, .m_axi_rresp, .m_axi_rlast,
        .m_axi_rvalid, .m_axi_rready
    );

    tag_pool #(.CAPACITY(TAG_CAPACITY)) tags (
        .clk, .rst_n(datapath_rst_n), .allocate(tag_allocate), .allocate_ready(tag_allocate_ready),
        .allocated_tag, .release_valid(tag_release), .released_tag, .free_count()
    );
    noc_model_core #(
        .ROWS(ROWS), .COLS(COLS), .VC_NUM(VC_NUM), .BUFFER_DEPTH(BUFFER_DEPTH),
        .TAG_WIDTH(TAG_WIDTH), .STATS_COUNTER_BITS(STATS_COUNTER_BITS)
    ) core (
        .clk, .rst_n(datapath_rst_n), .model_step, .step_ready(core_step_ready), .valiant, .jump_valid, .jump_cycle,
        .event_valid, .event_ready, .event_tag(head_tag), .event_dst(head_dst), .event_mid(head_mid),
        .event_flit_num(head_flit_num), .completion_valid, .completion_ready,
        .completion_tag, .completion_cycle, .logical_cycle, .network_idle(network_idle_raw),
        .clear_stats_epoch, .stats_epoch_needed, .stats_pipeline_idle,
        .stat_flits, .stat_heads, .stat_blocked, .stat_contended
    );

    assign proposed_completion = page_align(EVENTS_BASE + ({32'b0, command_word[95:64]} << 4));
    assign proposed_stats = page_align(proposed_completion + ({32'b0, command_word[95:64]} << 4));
    always_comb begin
        command_error = 0;
        if (command_word[63:0] != CONTROL_MAGIC) command_error = ERR_BAD_MAGIC;
        else if (command_word[127:96] > ROUTING_VALIANT) command_error = ERR_BAD_ROUTING;
        else if (proposed_stats + page_align(64'(LINK_COUNT) * 32) > DDR_LIMIT)
            command_error = ERR_BAD_RANGE;
    end
    assign descriptor_count = descriptor_words[descriptor_index >> 2][32 * (int'(descriptor_index) % 4) +: 32];
    assign feeder_invalid = cached_event[79:64] >= ENDPOINTS ||
        cached_event[79:64] == feeder_source || cached_event[127:96] == 0 ||
        (valiant && cached_event[95:80] >= ENDPOINTS) ||
        (source_meta[128] && cached_event[63:0] < source_meta[127:64]);
    assign tag_allocate = main_state == S_FEED_PROMOTE && !feeder_invalid && tag_allocate_ready;
    assign tag_release = main_state == S_COLLECT_STORE;
    assign released_tag = completion_pending_tag[completion_scan_index];
    assign completion_ready = ~completion_pending;
    assign all_sources_known = !(|source_needs_head);
    assign all_sources_finished = !(|source_active);
    assign idle_confirmed = network_idle_sampled && !model_step_previous;
    assign model_complete = all_sources_finished && idle_confirmed;
    assign idle_jump_needed = event_due_ready && idle_confirmed && !(|event_valid) && !all_sources_finished;
    assign jump_valid = main_state == S_JUMP_APPLY;
    always_ff @(posedge clk) begin
        if (!datapath_rst_n) model_step <= 1'b0;
        else model_step <= !model_step && core_step_ready && !stats_epoch_needed &&
            (jump_valid || (main_state == S_RUN && run_permitted));
    end
    assign clear_stats_epoch = main_state == S_ACC_CLEAR;
    always_ff @(posedge clk) begin
        if (!datapath_rst_n) begin
            event_valid <= '0;
            event_due_ready <= 1'b0;
            run_permitted <= 1'b0;
        end else begin
            // Compare timestamps during physical preparation, ahead of the
            // high-fanout commit enable. Head promotion and time changes invalidate it.
            for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
                event_valid[endpoint] <= head_valid[endpoint] && head_send_time[endpoint] <= logical_cycle;
            end
            event_due_ready <= !model_step && !tag_allocate;
            run_permitted <= event_due_ready && all_sources_known && !stats_epoch_needed &&
                !(|completion_pending) && !model_complete && !idle_jump_needed &&
                !(network_idle_sampled && model_step_previous) && logical_cycle != 64'hffff_ffff_ffff_ffff;
        end
    end
    always_ff @(posedge clk) begin
        // Register the selected counter before the 64-bit accumulation adder.
        if (main_state == S_ACC_READ) begin
            case (stats_index[1:0])
                0: stats_addend <= 64'(stat_flits[stats_index >> 2]);
                1: stats_addend <= 64'(stat_heads[stats_index >> 2]);
                2: stats_addend <= 64'(stat_blocked[stats_index >> 2]);
                default: stats_addend <= 64'(stat_contended[stats_index >> 2]);
            endcase
        end
    end

    // Synchronous memories keep context, prefetch and cumulative statistics in BRAM.
    always_ff @(posedge clk) begin
        if (main_state == S_PARSE && descriptor_sum + descriptor_count <= event_count)
            source_state[descriptor_index] <= {1'b0, 64'b0, descriptor_count, descriptor_sum[31:0]};
        else if (tag_allocate)
            source_state[feeder_source] <= {1'b1, cached_event[63:0],
                (source_meta[63:32] - 32'd1), (source_meta[31:0] + 32'd1)};
        if (main_state == S_FEED_META) source_meta <= source_state[feeder_source];
        if (main_state == S_FEED_DATA && rd_data_valid)
            event_cache[{feeder_source, fetch_index}] <= rd_data;
        if (main_state == S_FEED_CACHE && cache_count[feeder_source] != 0)
            cached_event <= event_cache[{feeder_source, cache_position[feeder_source]}];
        if (tag_allocate) context_table[allocated_tag] <= source_meta[31:0];
        if (main_state == S_COLLECT_READ)
            context_read_key <= context_table[completion_pending_tag[completion_scan_index]];
        if (main_state == S_INIT_STATS) stats_total[stats_index] <= '0;
        else if (main_state == S_ACC_ADD) stats_total[stats_index] <= stats_read_value + stats_addend;
        if (main_state == S_ACC_READ || main_state == S_EXPORT_READ)
            stats_read_value <= stats_total[main_state == S_ACC_READ ? stats_index : export_index];
    end

    always_comb begin
        rd_cmd_valid = 1'b0;
        rd_cmd_addr = '0;
        rd_cmd_beats = 1;
        rd_data_ready = 1'b1;
        case (main_state)
            S_POLL_CMD: begin rd_cmd_valid = 1'b1; rd_cmd_addr = CONTROL_ADDR; end
            S_DESC_CMD: begin
                rd_cmd_valid = 1'b1;
                rd_cmd_addr = CONTROL_ADDR + 32;
                rd_cmd_beats = 5'(DESC_BEATS);
            end
            S_FEED_CMD: begin
                rd_cmd_valid = 1'b1;
                rd_cmd_addr = EVENTS_BASE + ({32'b0, source_meta[31:0]} << 4);
                rd_cmd_beats = fetch_beats;
            end
            default: begin end
        endcase
        wr_cmd_valid = main_state == S_WRITE_CMD;
        wr_cmd_addr = write_address;
        wr_cmd_beats = write_beats;
        wr_data_valid = main_state == S_WRITE_DATA;
        wr_data = write_buffer[write_index[3:0]];
        wr_data_strb = 16'hffff;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            memory_ready_sync <= '0;
            network_idle_sampled <= 1'b1;
            model_step_previous <= 1'b0;
        end else begin
            memory_ready_sync <= {memory_ready_sync[0], memory_ready};
            network_idle_sampled <= network_idle_raw;
            model_step_previous <= model_step;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            main_state <= S_BOOT_WAIT;
            after_write <= S_WAIT;
            flush_resume <= S_RUN;
            poll_counter <= '0;
            command_word <= '0;
            event_count <= '0;
            completion_written <= '0;
            valiant <= 1'b0;
            error_code <= '0;
            datapath_rst_n <= 1'b0;
            completion_base <= '0;
            stats_base <= '0;
            write_address <= '0;
            write_beats <= '0;
            write_index <= '0;
            buffer_count <= '0;
            completion_flush <= 1'b0;
            descriptor_beat <= '0;
            descriptor_index <= '0;
            descriptor_sum <= '0;
            feeder_source <= '0;
            fetch_beats <= '0;
            fetch_index <= '0;
            cache_count <= '0;
            cache_position <= '0;
            head_valid <= '0;
            head_has_next <= '0;
            source_needs_head <= '0;
            source_active <= '0;
            head_send_time <= '0;
            head_dst <= '0;
            head_mid <= '0;
            head_flit_num <= '0;
            head_tag <= '0;
            completion_pending <= '0;
            completion_pending_tag <= '0;
            completion_scan_index <= '0;
            completion_wave_cycle <= '0;
            jump_cycle <= '0;
            jump_index <= '0;
            stats_final <= 1'b0;
            stats_index <= '0;
            export_index <= '0;
            export_low <= '0;
            stats_write_address <= '0;
        end else begin
            if (model_step) begin
                for (int source = 0; source < ENDPOINTS; source++) begin
                    if (event_valid[source] && event_ready[source]) begin
                        head_valid[source] <= 1'b0;
                        source_needs_head[source] <= head_has_next[source];
                        source_active[source] <= head_has_next[source];
                    end
                    if (completion_valid[source] && completion_ready[source]) begin
                        completion_pending[source] <= 1'b1;
                        completion_pending_tag[source] <= completion_tag[source];
                    end
                end
                if (|completion_valid) completion_wave_cycle <= completion_cycle;
            end
            if (rd_error || wr_error) begin
                error_code <= wr_error ? ERR_AXI_WRITE : (rd_error_rlast ? ERR_AXI_RLAST : ERR_AXI_READ);
                completion_flush <= 1'b0;
                main_state <= S_ERROR_CLEAR;
            end else case (main_state)
                S_BOOT_WAIT: if (memory_ready_sync[1]) main_state <= S_BOOT_CLEAR;
                S_BOOT_CLEAR: begin
                    write_buffer[0] <= '0;
                    start_write(CONTROL_ADDR, 1, S_BOOT_STATUS);
                end
                S_BOOT_STATUS: begin
                    write_buffer[0] <= {64'b0, 32'b0, 16'b0, STATE_IDLE};
                    start_write(CONTROL_ADDR + 16, 1, S_WAIT);
                end
                S_WAIT: begin
                    if (!memory_ready_sync[1]) poll_counter <= '0;
                    else if (poll_counter + 1 >= POLL_INTERVAL) begin
                        poll_counter <= '0;
                        main_state <= S_POLL_CMD;
                    end else poll_counter <= poll_counter + 1'b1;
                end
                S_POLL_CMD: if (rd_cmd_ready) main_state <= S_POLL_DATA;
                S_POLL_DATA: if (rd_data_valid) begin command_word <= rd_data; main_state <= S_CHECK; end
                S_CHECK: begin
                    if (command_word[63:0] == 0) main_state <= S_WAIT;
                    else begin
                        event_count <= command_word[95:64];
                        valiant <= command_word[127:96] == ROUTING_VALIANT;
                        error_code <= command_error;
                        completion_base <= proposed_completion;
                        stats_base <= proposed_stats;
                        datapath_rst_n <= 1'b0;
                        head_valid <= '0;
                        source_needs_head <= '0;
                        source_active <= '0;
                        cache_count <= '0;
                        cache_position <= '0;
                        completion_pending <= '0;
                        completion_written <= '0;
                        buffer_count <= '0;
                        completion_flush <= 1'b0;
                        stats_index <= '0;
                        feeder_source <= '0;
                        completion_scan_index <= '0;
                        main_state <= S_MARK_RUNNING;
                    end
                end
                S_MARK_RUNNING: begin
                    write_buffer[0] <= {64'b0, 32'b0, 16'b0, STATE_RUNNING};
                    start_write(CONTROL_ADDR + 16, 1, S_ACK);
                end
                S_ACK: begin
                    write_buffer[0] <= '0;
                    start_write(CONTROL_ADDR, 1, error_code == 0 ? S_INIT_STATS : S_ERROR_STATUS);
                end
                S_INIT_STATS: begin
                    if (stats_index == STAT_VALUES - 1) begin
                        stats_index <= '0;
                        descriptor_beat <= '0;
                        descriptor_index <= '0;
                        descriptor_sum <= '0;
                        main_state <= S_DESC_CMD;
                    end else stats_index <= stats_index + 1'b1;
                end
                S_DESC_CMD: if (rd_cmd_ready) main_state <= S_DESC_DATA;
                S_DESC_DATA: if (rd_data_valid) begin
                    descriptor_words[descriptor_beat] <= rd_data;
                    if (rd_data_last) main_state <= S_PARSE;
                    else descriptor_beat <= descriptor_beat + 1'b1;
                end
                S_PARSE: begin
                    if (descriptor_sum + descriptor_count > event_count ||
                        (descriptor_index == ENDPOINTS - 1 && descriptor_sum + descriptor_count != event_count)) begin
                        error_code <= ERR_BAD_RANGE;
                        main_state <= S_ERROR_CLEAR;
                    end else begin
                        descriptor_sum <= descriptor_sum + descriptor_count;
                        source_needs_head[descriptor_index] <= descriptor_count != 0;
                        source_active[descriptor_index] <= descriptor_count != 0;
                        if (descriptor_index == ENDPOINTS - 1) main_state <= S_START;
                        else descriptor_index <= descriptor_index + 1'b1;
                    end
                end
                S_START: begin datapath_rst_n <= 1'b1; main_state <= S_RUN; end
                S_RUN: begin
                    if (|completion_pending) begin
                        if (completion_pending[completion_scan_index]) main_state <= S_COLLECT_READ;
                        else completion_scan_index <= completion_scan_index == ENDPOINTS - 1 ? '0 : completion_scan_index + 1'b1;
                    end else if (stats_epoch_needed) begin
                        if (stats_pipeline_idle) begin
                            stats_final <= 1'b0;
                            stats_index <= '0;
                            main_state <= S_ACC_READ;
                        end
                    end else if (model_complete && stats_pipeline_idle) begin
                        if (buffer_count != 0) begin
                            flush_resume <= S_RUN;
                            main_state <= S_FLUSH;
                        end else if (completion_written != event_count) begin
                            error_code <= ERR_INTERNAL;
                            main_state <= S_ERROR_CLEAR;
                        end else begin
                            stats_final <= 1'b1;
                            stats_index <= '0;
                            main_state <= S_ACC_READ;
                        end
                    end else if (!all_sources_known) begin
                        if (source_needs_head[feeder_source]) main_state <= S_FEED_META;
                        else feeder_source <= feeder_source == ENDPOINTS - 1 ? '0 : feeder_source + 1'b1;
                    end else if (idle_jump_needed) begin
                        jump_index <= '0;
                        jump_cycle <= '1;
                        main_state <= S_JUMP_SCAN;
                    end else if (logical_cycle == 64'hffff_ffff_ffff_ffff) begin
                        error_code <= ERR_BAD_RANGE;
                        main_state <= S_ERROR_CLEAR;
                    end
                end
                S_FEED_META: main_state <= S_FEED_CACHE;
                S_FEED_CACHE: begin
                    if (cache_count[feeder_source] != 0) main_state <= S_FEED_PROMOTE;
                    else begin
                        fetch_beats <= source_meta[63:32] >= 16 ? 5'd16 : source_meta[36:32];
                        fetch_index <= '0;
                        main_state <= S_FEED_CMD;
                    end
                end
                S_FEED_CMD: if (rd_cmd_ready) main_state <= S_FEED_DATA;
                S_FEED_DATA: if (rd_data_valid) begin
                    if (rd_data_last) begin
                        cache_count[feeder_source] <= fetch_beats;
                        cache_position[feeder_source] <= '0;
                        main_state <= S_FEED_CACHE;
                    end else fetch_index <= fetch_index + 1'b1;
                end
                S_FEED_PROMOTE: begin
                    if (feeder_invalid) begin error_code <= ERR_BAD_RANGE; main_state <= S_ERROR_CLEAR; end
                    else if (tag_allocate_ready) begin
                        head_valid[feeder_source] <= 1'b1;
                        head_has_next[feeder_source] <= source_meta[63:32] > 1;
                        head_send_time[feeder_source] <= cached_event[63:0];
                        head_dst[feeder_source] <= cached_event[64 +: ENDPOINT_BITS];
                        head_mid[feeder_source] <= cached_event[80 +: ENDPOINT_BITS];
                        head_flit_num[feeder_source] <= cached_event[127:96];
                        head_tag[feeder_source] <= allocated_tag;
                        source_needs_head[feeder_source] <= 1'b0;
                        cache_count[feeder_source] <= cache_count[feeder_source] - 1'b1;
                        cache_position[feeder_source] <= cache_position[feeder_source] + 1'b1;
                        feeder_source <= feeder_source == ENDPOINTS - 1 ? '0 : feeder_source + 1'b1;
                        main_state <= S_RUN;
                    end
                end
                S_COLLECT_READ: main_state <= S_COLLECT_STORE;
                S_COLLECT_STORE: begin
                    write_buffer[buffer_count[3:0]] <= {completion_wave_cycle, 32'b0, context_read_key};
                    completion_pending[completion_scan_index] <= 1'b0;
                    buffer_count <= buffer_count + 1'b1;
                    if (buffer_count == 15) begin flush_resume <= S_RUN; main_state <= S_FLUSH; end
                    else main_state <= S_RUN;
                end
                S_FLUSH: begin
                    completion_flush <= 1'b1;
                    start_write(completion_base + ({32'b0, completion_written} << 4), buffer_count, flush_resume);
                    buffer_count <= '0;
                end
                S_ACC_READ: main_state <= S_ACC_ADD;
                S_ACC_ADD: begin
                    if (stats_index == STAT_VALUES - 1) main_state <= S_ACC_CLEAR;
                    else begin stats_index <= stats_index + 1'b1; main_state <= S_ACC_READ; end
                end
                S_ACC_CLEAR: begin
                    if (stats_final) begin
                        export_index <= '0;
                        buffer_count <= '0;
                        stats_write_address <= stats_base;
                        main_state <= S_EXPORT_READ;
                    end else main_state <= S_RUN;
                end
                S_EXPORT_READ: main_state <= S_EXPORT_PACK;
                S_EXPORT_PACK: begin
                    export_index <= export_index + 1'b1;
                    main_state <= S_EXPORT_READ;
                    if (!export_index[0]) export_low <= stats_read_value;
                    else begin
                        write_buffer[buffer_count[3:0]] <= {stats_read_value, export_low};
                        if (buffer_count == 15 || export_index == STAT_VALUES - 1) begin
                            start_write(stats_write_address, buffer_count + 1'b1,
                                export_index == STAT_VALUES - 1 ? S_DONE : S_EXPORT_READ);
                            stats_write_address <= stats_write_address + ((64'(buffer_count) + 1) << 4);
                            buffer_count <= '0;
                        end else buffer_count <= buffer_count + 1'b1;
                    end
                end
                S_DONE: begin
                    write_buffer[0] <= {logical_cycle, completion_written, 16'b0, STATE_DONE};
                    start_write(CONTROL_ADDR + 16, 1, S_FINISH);
                end
                S_ERROR_CLEAR: begin
                    write_buffer[0] <= '0;
                    start_write(CONTROL_ADDR, 1, S_ERROR_STATUS);
                end
                S_ERROR_STATUS: begin
                    write_buffer[0] <= {logical_cycle, completion_written, error_code, STATE_ERROR};
                    start_write(CONTROL_ADDR + 16, 1, S_FINISH);
                end
                S_FINISH: begin datapath_rst_n <= 1'b0; main_state <= S_WAIT; end
                S_JUMP_SCAN: begin
                    if (head_valid[jump_index] && head_send_time[jump_index] < jump_cycle)
                        jump_cycle <= head_send_time[jump_index];
                    if (jump_index == ENDPOINTS - 1) main_state <= S_JUMP_APPLY;
                    else jump_index <= jump_index + 1'b1;
                end
                S_JUMP_APPLY: if (model_step || stats_epoch_needed) main_state <= S_RUN;
                S_WRITE_CMD: if (wr_cmd_ready) main_state <= S_WRITE_DATA;
                S_WRITE_DATA: if (wr_data_ready) begin
                    if (write_index + 1'b1 == write_beats) main_state <= S_WRITE_RESPONSE;
                    else write_index <= write_index + 1'b1;
                end
                S_WRITE_RESPONSE: if (wr_done) begin
                    if (completion_flush) begin
                        completion_written <= completion_written + write_beats;
                        completion_flush <= 1'b0;
                    end
                    main_state <= after_write;
                end
                default: main_state <= S_WAIT;
            endcase
        end
    end
endmodule
