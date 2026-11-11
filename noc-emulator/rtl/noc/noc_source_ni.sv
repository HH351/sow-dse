`include "noc_defs.svh"

module noc_source_ni #(
    parameter int unsigned ROWS = 2,
    parameter int unsigned COLS = 2,
    parameter int unsigned VC_NUM = 2,
    parameter int unsigned SOURCE_ID = 0,
    parameter int unsigned TAG_WIDTH = 12,
    parameter int unsigned ENDPOINT_BITS = (ROWS * COLS <= 2) ? 1 : $clog2(ROWS * COLS),
    parameter int unsigned ROW_BITS = (ROWS <= 1) ? 1 : $clog2(ROWS),
    parameter int unsigned COL_BITS = (COLS <= 1) ? 1 : $clog2(COLS),
    parameter int unsigned DEST_BITS = ROW_BITS + COL_BITS,
    parameter int unsigned LEN_BITS = 32,
    parameter int unsigned FLIT_WIDTH = TAG_WIDTH + 2 * DEST_BITS + 2,
    localparam int unsigned VC_BITS = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM)
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         model_step,
    input  logic                         valiant,
    input  logic                         event_valid,
    output logic                         event_ready,
    input  logic [TAG_WIDTH-1:0]         event_tag,
    input  logic [ENDPOINT_BITS-1:0]     event_dst,
    input  logic [ENDPOINT_BITS-1:0]     event_mid,
    input  logic [LEN_BITS-1:0]          event_flit_num,
    output logic                         flit_valid,
    input  logic [VC_NUM-1:0]            flit_ready,
    output logic [FLIT_WIDTH-1:0]        flit_data,
    output logic [VC_BITS-1:0]           flit_vc,
    output logic                         contended,
    output logic                         idle
);
    logic [VC_NUM-1:0] active;
    logic [VC_NUM-1:0] first_flit;
    logic [VC_NUM-1:0][TAG_WIDTH-1:0] active_tag;
    logic [VC_NUM-1:0][DEST_BITS-1:0] active_dst;
    logic [VC_NUM-1:0][DEST_BITS-1:0] active_mid;
    logic [VC_NUM-1:0][LEN_BITS-1:0] remaining;
    logic [VC_BITS-1:0] rr_pointer;
    logic selected_valid;
    logic [VC_BITS-1:0] selected_vc;
    logic free_valid;
    logic [VC_BITS-1:0] free_vc;
    logic bypass;
    logic send;
    logic [DEST_BITS-1:0] event_destination;
    logic [DEST_BITS-1:0] event_middle;

    always_comb begin
        event_destination = '0;
        event_middle = {ROW_BITS'(event_mid / COLS), COL_BITS'(event_mid % COLS)};
        event_destination[COL_BITS-1:0] = COL_BITS'(event_dst % COLS);
        event_destination[COL_BITS +: ROW_BITS] = ROW_BITS'(event_dst / COLS);
    end

    always_comb begin
        selected_valid = 1'b0;
        selected_vc = '0;
        free_valid = 1'b0;
        free_vc = '0;
        for (int offset = 0; offset < VC_NUM; offset++) begin
            int candidate;
            candidate = rr_pointer + offset;
            if (candidate >= VC_NUM) candidate = candidate - VC_NUM;
            if (!selected_valid && active[candidate] && flit_ready[candidate]) begin
                selected_valid = 1'b1;
                selected_vc = VC_BITS'(candidate);
            end
        end
        for (int offset = 0; offset < VC_NUM; offset++) begin
            int candidate;
            candidate = rr_pointer + offset;
            if (candidate >= VC_NUM) candidate = candidate - VC_NUM;
            if (!selected_valid && active[candidate]) begin
                selected_valid = 1'b1;
                selected_vc = VC_BITS'(candidate);
            end
        end
        for (int vc = 0; vc < VC_NUM; vc++) begin
            if (!free_valid && !active[vc] &&
                (!valiant || ((vc >= VC_NUM / 2) == (event_mid == SOURCE_ID)))) begin
                free_valid = 1'b1;
                free_vc = VC_BITS'(vc);
            end
        end
    end

    assign bypass = event_valid && free_valid && !selected_valid;
    assign event_ready = free_valid && (!bypass || flit_ready[free_vc]);
    assign flit_valid = selected_valid || bypass;
    assign flit_vc = bypass ? free_vc : selected_vc;
    assign send = flit_valid && flit_ready[flit_vc];
    assign contended = ($countones(active) + (event_valid && free_valid)) > 1;
    assign idle = (active == '0);

    always_comb begin
        flit_data = '0;
        if (bypass) begin
            flit_data[TAG_WIDTH-1:0] = event_tag;
            flit_data[TAG_WIDTH +: DEST_BITS] = event_destination;
            flit_data[TAG_WIDTH+DEST_BITS+2 +: DEST_BITS] = event_middle;
            flit_data[TAG_WIDTH+DEST_BITS] = 1'b1;
            flit_data[TAG_WIDTH+DEST_BITS+1] = (event_flit_num == 1);
        end else if (selected_valid) begin
            flit_data[TAG_WIDTH-1:0] = active_tag[selected_vc];
            flit_data[TAG_WIDTH +: DEST_BITS] = active_dst[selected_vc];
            flit_data[TAG_WIDTH+DEST_BITS+2 +: DEST_BITS] = active_mid[selected_vc];
            flit_data[TAG_WIDTH+DEST_BITS] = first_flit[selected_vc];
            flit_data[TAG_WIDTH+DEST_BITS+1] = (remaining[selected_vc] == 1);
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active <= '0;
            first_flit <= '0;
            rr_pointer <= '0;
            active_tag <= '0;
            active_dst <= '0;
            active_mid <= '0;
            remaining <= '0;
        end else if (model_step) begin
            if (event_valid && event_ready && !bypass) begin
                active[free_vc] <= 1'b1;
                first_flit[free_vc] <= 1'b1;
                active_tag[free_vc] <= event_tag;
                active_dst[free_vc] <= event_destination;
                active_mid[free_vc] <= event_middle;
                remaining[free_vc] <= event_flit_num;
            end
            if (send) begin
                rr_pointer <= (flit_vc == VC_NUM - 1) ? '0 : flit_vc + 1'b1;
                if (bypass) begin
                    if (event_flit_num > 1) begin
                        active[free_vc] <= 1'b1;
                        first_flit[free_vc] <= 1'b0;
                        active_tag[free_vc] <= event_tag;
                        active_dst[free_vc] <= event_destination;
                        active_mid[free_vc] <= event_middle;
                        remaining[free_vc] <= event_flit_num - 1'b1;
                    end
                end else if (remaining[selected_vc] == 1) begin
                    active[selected_vc] <= 1'b0;
                    first_flit[selected_vc] <= 1'b0;
                    remaining[selected_vc] <= '0;
                end else begin
                    first_flit[selected_vc] <= 1'b0;
                    remaining[selected_vc] <= remaining[selected_vc] - 1'b1;
                end
            end
        end
    end

endmodule
