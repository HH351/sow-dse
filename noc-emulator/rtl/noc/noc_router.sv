`include "noc_defs.svh"

module noc_router #(
    parameter int unsigned ROWS = 2,
    parameter int unsigned COLS = 2,
    parameter int unsigned ROUTER_ID = 0,
    parameter int unsigned VC_NUM = 2,
    parameter int unsigned BUFFER_DEPTH = 8,
    parameter int unsigned TAG_WIDTH = 8,
    parameter int unsigned ROW_BITS = (ROWS <= 1) ? 1 : $clog2(ROWS),
    parameter int unsigned COL_BITS = (COLS <= 1) ? 1 : $clog2(COLS),
    parameter int unsigned DEST_BITS = ROW_BITS + COL_BITS,
    parameter int unsigned FLIT_WIDTH = TAG_WIDTH + 2 * DEST_BITS + 2,
    localparam int unsigned PORTS = 5,
    localparam int unsigned DIRS = 4,
    localparam int unsigned VC_BITS = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM),
    localparam int unsigned REQUESTS = PORTS * VC_NUM,
    localparam int unsigned REQ_BITS = (REQUESTS <= 1) ? 1 : $clog2(REQUESTS)
) (
    input  logic                                  clk,
    input  logic                                  rst_n,
    input  logic                                  model_step,
    input  logic                                  valiant,
    input  logic [PORTS-1:0]                      in_valid,
    output logic [PORTS-1:0]                      in_ready,
    output logic [PORTS-1:0][VC_NUM-1:0]          in_vc_ready,
    output logic [PORTS-1:0][VC_NUM-1:0]          in_credit_return,
    input  logic [PORTS-1:0][FLIT_WIDTH-1:0]      in_data,
    input  logic [PORTS-1:0][VC_BITS-1:0]         in_vc,
    output logic [DIRS-1:0]                       out_valid,
    input  logic [DIRS-1:0]                       out_ready,
    input  logic [DIRS-1:0][VC_NUM-1:0]           out_credit_available,
    output logic [DIRS-1:0][FLIT_WIDTH-1:0]       out_data,
    output logic [DIRS-1:0][VC_BITS-1:0]          out_vc,
    output logic [DIRS-1:0]                       out_requested,
    output logic [DIRS-1:0]                       out_contended,
    output logic                                  idle
);
    logic [PORTS-1:0][VC_NUM-1:0] fifo_push;
    logic [PORTS-1:0][VC_NUM-1:0] fifo_pop;
    logic [PORTS-1:0][VC_NUM-1:0] fifo_empty;
    logic [PORTS-1:0][VC_NUM-1:0] fifo_full;
    logic [PORTS-1:0][VC_NUM-1:0][FLIT_WIDTH-1:0] fifo_front;
    logic [DIRS-1:0][REQUESTS-1:0] demand;
    logic [DIRS-1:0][REQUESTS-1:0] requests;
    logic [DIRS-1:0][REQUESTS-1:0] grants;
    logic [DIRS-1:0][REQUESTS-1:0] requests_raw, grants_raw;
    logic [DIRS-1:0][REQ_BITS-1:0] grant_index;
    logic [DIRS-1:0] grant_valid;
    logic [PORTS-1:0][VC_NUM-1:0] route_active;
    logic [PORTS-1:0][VC_NUM-1:0][1:0] route_direction;
    logic [DIRS-1:0][VC_NUM-1:0] output_vc_busy;
    logic [PORTS-1:0][VC_NUM-1:0][VC_BITS-1:0] route_output_vc;
    logic [PORTS-1:0][VC_NUM-1:0][VC_BITS-1:0] request_vc;
    logic [PORTS-1:0][VC_NUM-1:0][VC_BITS-1:0] request_vc_raw;
    logic [DIRS-1:0] requested_raw, contended_raw;

    // The within-half VC index is fixed; only the phase bit can change at mid.
    logic [PORTS-1:0][VC_NUM-1:0] route_second_phase;

    logic [REQUESTS-1:0][FLIT_WIDTH-1:0] flat_front;
    logic [REQUESTS-1:0][VC_BITS-1:0] flat_request_vc;
    assign flat_front = fifo_front;
    assign flat_request_vc = request_vc;

    function automatic bit at_middle(input logic [FLIT_WIDTH-1:0] flit);
        at_middle = flit[TAG_WIDTH+DEST_BITS+2 +: DEST_BITS] ==
            {ROW_BITS'(ROUTER_ID / COLS), COL_BITS'(ROUTER_ID % COLS)};
    endfunction

    function automatic logic [DEST_BITS-1:0] target_for(
        input logic [FLIT_WIDTH-1:0] flit, input int vc
    );
        if (valiant && vc < VC_NUM / 2 && !at_middle(flit))
            target_for = flit[TAG_WIDTH+DEST_BITS+2 +: DEST_BITS];
        else target_for = flit[TAG_WIDTH +: DEST_BITS];
    endfunction

    function automatic int route_for(input logic [DEST_BITS-1:0] destination);
        int dst_row;
        int dst_col;
        begin
            dst_col = destination[COL_BITS-1:0];
            dst_row = destination[COL_BITS +: ROW_BITS];
            if (dst_row > ROUTER_ID / COLS) route_for = `NOC_DIR_SOUTH;
            else if (dst_row != ROUTER_ID / COLS) route_for = `NOC_DIR_NORTH;
            else if (dst_col > ROUTER_ID % COLS) route_for = `NOC_DIR_EAST;
            else route_for = `NOC_DIR_WEST;
        end
    endfunction

    generate
        for (genvar port = 0; port < PORTS; port++) begin : g_port
            for (genvar vc = 0; vc < VC_NUM; vc++) begin : g_vc
                always_comb begin
                    route_output_vc[port][vc] = VC_BITS'(vc);
                    if (vc < VC_NUM / 2)
                        route_output_vc[port][vc][VC_BITS-1] = route_second_phase[port][vc];
                end
                vc_fifo #(.WIDTH(FLIT_WIDTH), .DEPTH(BUFFER_DEPTH)) fifo (
                    .clk, .rst_n, .model_step,
                    .push(fifo_push[port][vc]), .push_data(in_data[port]),
                    .pop(fifo_pop[port][vc]), .front_data(fifo_front[port][vc]),
                    .empty(fifo_empty[port][vc]), .full(fifo_full[port][vc]), .count()
                );
            end
        end
        for (genvar dir = 0; dir < DIRS; dir++) begin : g_arbiter
            rr_arbiter #(.REQUESTS(REQUESTS)) arbiter (
                .clk, .rst_n, .model_step, .request(requests[dir]),
                .advance(out_ready[dir]), .grant(grants_raw[dir]),
                .grant_index(grant_index[dir]), .grant_valid(grant_valid[dir])
            );
        end
    endgenerate

    assign in_vc_ready = ~fifo_full;
    assign in_credit_return = fifo_pop;

    always_comb begin
        demand = '0;
        request_vc_raw = '0;
        requests_raw = '0;
        output_vc_busy = '0;
        requested_raw = '0;
        contended_raw = '0;
        idle = !(|route_active);
        for (int direction = 0; direction < DIRS; direction++) begin
            for (int vc = 0; vc < VC_NUM; vc++) begin
                for (int port = 0; port < PORTS; port++) begin
                    output_vc_busy[direction][vc] |= route_active[port][vc] &&
                        route_direction[port][vc] == direction &&
                        (vc >= VC_NUM / 2 || !route_second_phase[port][vc]);
                    if (vc >= VC_NUM / 2) begin
                        output_vc_busy[direction][vc] |= route_active[port][vc - VC_NUM / 2] &&
                            route_direction[port][vc - VC_NUM / 2] == direction &&
                            route_second_phase[port][vc - VC_NUM / 2];
                    end
                end
            end
        end
        for (int port = 0; port < PORTS; port++) begin
            for (int vc = 0; vc < VC_NUM; vc++) begin
                int direction;
                direction = 0;
                request_vc_raw[port][vc] = route_active[port][vc] ? route_output_vc[port][vc] :
                    VC_BITS'(vc + ((valiant && vc < VC_NUM / 2 && at_middle(fifo_front[port][vc])) ? VC_NUM / 2 : 0));
                if (!fifo_empty[port][vc]) begin
                    idle = 1'b0;
                    direction = route_active[port][vc] ? route_direction[port][vc] :
                        route_for(target_for(fifo_front[port][vc], vc));
                    demand[direction][port * VC_NUM + vc] = 1'b1;
                    if ((route_active[port][vc] || !output_vc_busy[direction][request_vc_raw[port][vc]]) &&
                        out_credit_available[direction][request_vc_raw[port][vc]]) begin
                        requests_raw[direction][port * VC_NUM + vc] = 1'b1;
                    end
                end
            end
        end
        for (int direction = 0; direction < DIRS; direction++) begin
            requested_raw[direction] = |demand[direction];
            contended_raw[direction] =
                |(demand[direction] & (demand[direction] - 1'b1));
        end
    end

    // Two physical preparation stages. Architectural state changes only on
    // model_step, after both stages have observed the current NoC state.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            requests <= '0;
            request_vc <= '0;
            out_requested <= '0;
            out_contended <= '0;
            grants <= '0;
            out_valid <= '0;
            out_data <= '0;
            out_vc <= '0;
        end else begin
            requests <= requests_raw;
            request_vc <= request_vc_raw;
            out_requested <= requested_raw;
            out_contended <= contended_raw;
            grants <= grants_raw;
            out_valid <= grant_valid;
            for (int direction = 0; direction < DIRS; direction++) begin
                out_data[direction] <= grant_valid[direction] ? flat_front[grant_index[direction]] : '0;
                out_vc[direction] <= grant_valid[direction] ? flat_request_vc[grant_index[direction]] : '0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            route_active <= '0;
            route_direction <= '0;
            route_second_phase <= '0;
        end else if (model_step) begin
            for (int direction = 0; direction < DIRS; direction++) begin
                for (int port = 0; port < PORTS; port++) begin
                    for (int vc = 0; vc < VC_NUM; vc++) begin
                        if (grants[direction][port * VC_NUM + vc] && out_ready[direction]) begin
                            if (fifo_front[port][vc][TAG_WIDTH+DEST_BITS+1]) begin
                                route_active[port][vc] <= 1'b0;
                            end else if (!route_active[port][vc]) begin
                                route_active[port][vc] <= 1'b1;
                                route_direction[port][vc] <= 2'(direction);
                                route_second_phase[port][vc] <= request_vc[port][vc][VC_BITS-1];
                            end
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        fifo_push = '0;
        fifo_pop = '0;
        in_ready = '0;
        for (int direction = 0; direction < DIRS; direction++) begin
            for (int port = 0; port < PORTS; port++) begin
                for (int vc = 0; vc < VC_NUM; vc++) begin
                    if (grants[direction][port * VC_NUM + vc]) begin
                        fifo_pop[port][vc] = out_ready[direction];
                    end
                end
            end
        end
        for (int port = 0; port < PORTS; port++) begin
            if (in_vc[port] < VC_NUM) begin
                in_ready[port] = in_vc_ready[port][in_vc[port]];
                fifo_push[port][in_vc[port]] = in_valid[port] && in_ready[port];
            end
        end
    end

endmodule
