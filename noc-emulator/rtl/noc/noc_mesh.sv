`include "noc_defs.svh"

module noc_mesh #(
    parameter int unsigned ROWS = 2,
    parameter int unsigned COLS = 2,
    parameter int unsigned VC_NUM = 2,
    parameter int unsigned BUFFER_DEPTH = 8,
    parameter int unsigned TAG_WIDTH = 8,
    parameter int unsigned ENDPOINT_BITS = 6,
    parameter int unsigned ROW_BITS = (ROWS <= 1) ? 1 : $clog2(ROWS),
    parameter int unsigned COL_BITS = (COLS <= 1) ? 1 : $clog2(COLS),
    parameter int unsigned DEST_BITS = ROW_BITS + COL_BITS,
    parameter int unsigned LEN_BITS = 32,
    parameter int unsigned ENDPOINTS = ROWS * COLS,
    parameter int unsigned INTERNAL_LINKS = 2 * (ROWS * (COLS - 1) + (ROWS - 1) * COLS),
    parameter int unsigned LINK_COUNT = 2 * ENDPOINTS + INTERNAL_LINKS,
    parameter int unsigned FLIT_WIDTH = TAG_WIDTH + 2 * DEST_BITS + 2,
    localparam int unsigned VC_BITS = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM),
    localparam int unsigned ROUTER_REQUESTS = 5 * VC_NUM,
    localparam int unsigned ROUTER_REQ_BITS = (ROUTER_REQUESTS <= 1) ? 1 : $clog2(ROUTER_REQUESTS)
) (
    input  logic                                      clk,
    input  logic                                      rst_n,
    input  logic                                      model_step,
    input  logic                                      valiant,
    input  logic [ENDPOINTS-1:0]                      event_valid,
    output logic [ENDPOINTS-1:0]                      event_ready,
    input  logic [ENDPOINTS-1:0][TAG_WIDTH-1:0]       event_tag,
    input  logic [ENDPOINTS-1:0][ENDPOINT_BITS-1:0]   event_dst,
    input  logic [ENDPOINTS-1:0][ENDPOINT_BITS-1:0]   event_mid,
    input  logic [ENDPOINTS-1:0][LEN_BITS-1:0]        event_flit_num,
    output logic [ENDPOINTS-1:0]                      completion_valid,
    input  logic [ENDPOINTS-1:0]                      completion_ready,
    output logic [ENDPOINTS-1:0][TAG_WIDTH-1:0]       completion_tag,
    output logic [LINK_COUNT-1:0]                     stat_transfer,
    output logic [LINK_COUNT-1:0]                     stat_packet_head,
    output logic [LINK_COUNT-1:0]                     stat_no_credit,
    output logic [LINK_COUNT-1:0]                     stat_contended,
    output logic                                      network_idle
);
    localparam int unsigned PORTS = 5;
    localparam int unsigned DIRS = 4;
    localparam int unsigned INTERNAL_BASE = ENDPOINTS;
    localparam int unsigned EJECTION_BASE = ENDPOINTS + INTERNAL_LINKS;
    localparam int unsigned CREDIT_BITS = $clog2(BUFFER_DEPTH + 1);

    logic [ENDPOINTS-1:0] source_valid;
    logic [ENDPOINTS-1:0][VC_NUM-1:0] source_ready;
    logic [ENDPOINTS-1:0][FLIT_WIDTH-1:0] source_data;
    logic [ENDPOINTS-1:0][VC_BITS-1:0] source_vc;
    logic [ENDPOINTS-1:0] source_contended;
    logic [ENDPOINTS-1:0] source_idle;

    logic [ENDPOINTS-1:0][PORTS-1:0] router_in_valid;
    logic [ENDPOINTS-1:0][PORTS-1:0] router_in_ready;
    logic [ENDPOINTS-1:0][PORTS-1:0][VC_NUM-1:0] router_in_vc_ready;
    logic [ENDPOINTS-1:0][PORTS-1:0][VC_NUM-1:0] router_in_credit_return;
    logic [ENDPOINTS-1:0][PORTS-1:0][FLIT_WIDTH-1:0] router_in_data;
    logic [ENDPOINTS-1:0][PORTS-1:0][VC_BITS-1:0] router_in_vc;
    logic [ENDPOINTS-1:0][DIRS-1:0] router_out_valid;
    logic [ENDPOINTS-1:0][DIRS-1:0] router_out_ready;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_NUM-1:0] router_out_credit_available;
    logic [ENDPOINTS-1:0][DIRS-1:0][FLIT_WIDTH-1:0] router_out_data;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_BITS-1:0] router_out_vc;
    logic [ENDPOINTS-1:0][DIRS-1:0] router_requested;
    logic [ENDPOINTS-1:0][DIRS-1:0] router_contended;
    logic [ENDPOINTS-1:0] router_idle;

    logic [ENDPOINTS-1:0][DIRS-1:0] link_valid;
    logic [ENDPOINTS-1:0][DIRS-1:0][FLIT_WIDTH-1:0] link_data;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_BITS-1:0] link_vc;
    logic [ENDPOINTS-1:0][DIRS-1:0] link_accept;
    logic [ENDPOINTS-1:0][DIRS-1:0] link_accept_raw;
    logic [ENDPOINTS-1:0][DIRS-1:0] link_can_load;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_NUM-1:0][CREDIT_BITS-1:0] link_credit;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_NUM-1:0] link_credit_return;
    logic [ENDPOINTS-1:0][DIRS-1:0][VC_NUM-1:0] link_credit_consume;

    logic [ENDPOINTS-1:0][DIRS-1:0] eject_request;
    logic [ENDPOINTS-1:0][DIRS-1:0] eject_request_raw;
    logic [ENDPOINTS-1:0][DIRS-1:0] link_final, link_final_raw;
    logic [ENDPOINTS-1:0][DIRS-1:0] eject_grant;
    logic [ENDPOINTS-1:0][DIRS-1:0] eject_grant_raw;
    logic [ENDPOINTS-1:0][1:0] eject_grant_index;
    logic [ENDPOINTS-1:0][1:0] eject_grant_index_raw;
    logic [ENDPOINTS-1:0] eject_grant_valid;
    logic [ENDPOINTS-1:0] eject_grant_valid_raw;
    logic [ENDPOINTS-1:0] eject_advance;
    logic [ENDPOINTS-1:0] eject_advance_raw;
    logic [ENDPOINTS-1:0] completion_valid_raw;
    logic [ENDPOINTS-1:0][TAG_WIDTH-1:0] completion_tag_raw;
    logic [ENDPOINTS-1:0] eject_head, eject_head_raw;

    function automatic bit has_neighbor(input int endpoint, input int direction);
        int row;
        int col;
        begin
            row = endpoint / COLS;
            col = endpoint % COLS;
            case (direction)
                `NOC_DIR_NORTH: has_neighbor = row > 0;
                `NOC_DIR_EAST:  has_neighbor = col + 1 < COLS;
                `NOC_DIR_SOUTH: has_neighbor = row + 1 < ROWS;
                default:        has_neighbor = col > 0;
            endcase
        end
    endfunction

    function automatic int neighbor_of(input int endpoint, input int direction);
        case (direction)
            `NOC_DIR_NORTH: neighbor_of = endpoint - COLS;
            `NOC_DIR_EAST:  neighbor_of = endpoint + 1;
            `NOC_DIR_SOUTH: neighbor_of = endpoint + COLS;
            default:        neighbor_of = endpoint - 1;
        endcase
    endfunction

    function automatic int neighbor_input_port(input int direction);
        case (direction)
            `NOC_DIR_NORTH: neighbor_input_port = `NOC_PORT_SOUTH;
            `NOC_DIR_EAST:  neighbor_input_port = `NOC_PORT_WEST;
            `NOC_DIR_SOUTH: neighbor_input_port = `NOC_PORT_NORTH;
            default:        neighbor_input_port = `NOC_PORT_EAST;
        endcase
    endfunction

    function automatic int incoming_slot(input int direction);
        incoming_slot = direction;
    endfunction

    function automatic int compact_internal_id(input int endpoint, input int direction);
        int row;
        int col;
        int horizontal_links;
        begin
            row = endpoint / COLS;
            col = endpoint % COLS;
            horizontal_links = 2 * ROWS * (COLS - 1);
            case (direction)
                `NOC_DIR_EAST:
                    compact_internal_id = 2 * (row * (COLS - 1) + col);
                `NOC_DIR_WEST:
                    compact_internal_id = 2 * (row * (COLS - 1) + col - 1) + 1;
                `NOC_DIR_SOUTH:
                    compact_internal_id = horizontal_links + 2 * (row * COLS + col);
                default:
                    compact_internal_id = horizontal_links + 2 * ((row - 1) * COLS + col) + 1;
            endcase
        end
    endfunction

    function automatic bit destination_matches(
        input logic [DEST_BITS-1:0] destination,
        input int endpoint
    );
        destination_matches =
            destination[COL_BITS-1:0] == COL_BITS'(endpoint % COLS) &&
            destination[COL_BITS +: ROW_BITS] == ROW_BITS'(endpoint / COLS);
    endfunction

    function automatic bit final_ejection(
        input logic [FLIT_WIDTH-1:0] flit,
        input logic [VC_BITS-1:0] vc,
        input int endpoint
    );
        final_ejection = destination_matches(flit[TAG_WIDTH +: DEST_BITS], endpoint) &&
            (!valiant || vc >= VC_NUM / 2 ||
             destination_matches(flit[TAG_WIDTH+DEST_BITS+2 +: DEST_BITS], endpoint));
    endfunction

    generate
        for (genvar endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin : g_endpoint
            noc_source_ni #(
                .ROWS(ROWS), .COLS(COLS), .VC_NUM(VC_NUM), .TAG_WIDTH(TAG_WIDTH),
                .ENDPOINT_BITS(ENDPOINT_BITS), .LEN_BITS(LEN_BITS), .SOURCE_ID(endpoint)
            ) source (
                .clk, .rst_n, .model_step, .valiant,
                .event_valid(event_valid[endpoint]), .event_ready(event_ready[endpoint]),
                .event_tag(event_tag[endpoint]), .event_dst(event_dst[endpoint]),
                .event_mid(event_mid[endpoint]),
                .event_flit_num(event_flit_num[endpoint]),
                .flit_valid(source_valid[endpoint]), .flit_ready(source_ready[endpoint]),
                .flit_data(source_data[endpoint]), .flit_vc(source_vc[endpoint]),
                .contended(source_contended[endpoint]), .idle(source_idle[endpoint])
            );
            noc_router #(
                .ROWS(ROWS), .COLS(COLS), .ROUTER_ID(endpoint),
                .VC_NUM(VC_NUM), .BUFFER_DEPTH(BUFFER_DEPTH),
                .TAG_WIDTH(TAG_WIDTH)
            ) router (
                .clk, .rst_n, .model_step, .valiant,
                .in_valid(router_in_valid[endpoint]), .in_ready(router_in_ready[endpoint]),
                .in_vc_ready(router_in_vc_ready[endpoint]),
                .in_credit_return(router_in_credit_return[endpoint]),
                .in_data(router_in_data[endpoint]), .in_vc(router_in_vc[endpoint]),
                .out_valid(router_out_valid[endpoint]), .out_ready(router_out_ready[endpoint]),
                .out_credit_available(router_out_credit_available[endpoint]),
                .out_data(router_out_data[endpoint]), .out_vc(router_out_vc[endpoint]),
                .out_requested(router_requested[endpoint]),
                .out_contended(router_contended[endpoint]), .idle(router_idle[endpoint])
            );
            rr_arbiter #(.REQUESTS(DIRS)) ejection_arbiter (
                .clk, .rst_n, .model_step, .request(eject_request[endpoint]),
                .advance(eject_advance[endpoint]), .grant(eject_grant_raw[endpoint]),
                .grant_index(eject_grant_index_raw[endpoint]),
                .grant_valid(eject_grant_valid_raw[endpoint])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            link_final <= '0;
            eject_request <= '0;
            eject_grant <= '0;
            eject_grant_index <= '0;
            eject_grant_valid <= '0;
            link_accept <= '0;
            eject_advance <= '0;
            completion_valid <= '0;
            completion_tag <= '0;
            eject_head <= '0;
        end else begin
            link_final <= link_final_raw;
            eject_request <= eject_request_raw;
            eject_grant <= eject_grant_raw;
            eject_grant_index <= eject_grant_index_raw;
            eject_grant_valid <= eject_grant_valid_raw;
            // Third physical preparation stage: final-link selection and
            // backpressure settle before FIFO pops and credit updates commit.
            link_accept <= link_accept_raw;
            eject_advance <= eject_advance_raw;
            completion_valid <= completion_valid_raw;
            completion_tag <= completion_tag_raw;
            eject_head <= eject_head_raw;
        end
    end

    for (genvar endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin : g_source_credit
        assign source_ready[endpoint] = router_in_vc_ready[endpoint][`NOC_PORT_LOCAL];
        for (genvar direction = 0; direction < DIRS; direction++) begin : g_direction_credit
            if (has_neighbor(endpoint, direction)) begin : g_final_decode
                assign link_final_raw[endpoint][direction] = final_ejection(
                    link_data[endpoint][direction], link_vc[endpoint][direction],
                    neighbor_of(endpoint, direction));
            end else begin : g_no_final_decode
                assign link_final_raw[endpoint][direction] = 1'b0;
            end
            for (genvar vc = 0; vc < VC_NUM; vc++) begin : g_vc_credit
                assign router_out_credit_available[endpoint][direction][vc] =
                    link_credit[endpoint][direction][vc] != 0;
                if (has_neighbor(endpoint, direction)) begin : g_neighbor
                    assign link_credit_return[endpoint][direction][vc] =
                        router_in_credit_return[neighbor_of(endpoint, direction)]
                            [neighbor_input_port(direction)][vc] ||
                        (link_valid[endpoint][direction] &&
                         link_vc[endpoint][direction] == vc &&
                         link_final[endpoint][direction] && link_accept[endpoint][direction]);
                end else begin : g_boundary
                    assign link_credit_return[endpoint][direction][vc] = 1'b0;
                end
            end
        end
    end

    always_comb begin
        router_in_valid = '0;
        router_in_data = '0;
        router_in_vc = '0;
        eject_request_raw = '0;

        for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
            router_in_valid[endpoint][`NOC_PORT_LOCAL] = source_valid[endpoint];
            router_in_data[endpoint][`NOC_PORT_LOCAL] = source_data[endpoint];
            router_in_vc[endpoint][`NOC_PORT_LOCAL] = source_vc[endpoint];
            for (int direction = 0; direction < DIRS; direction++) begin
                if (has_neighbor(endpoint, direction)) begin
                    if (link_valid[endpoint][direction] && link_final_raw[endpoint][direction]) begin
                        eject_request_raw[neighbor_of(endpoint, direction)][incoming_slot(direction)] = 1'b1;
                    end
                    if (!link_final[endpoint][direction]) begin
                        router_in_valid[neighbor_of(endpoint, direction)][neighbor_input_port(direction)] =
                            link_valid[endpoint][direction];
                        router_in_data[neighbor_of(endpoint, direction)][neighbor_input_port(direction)] =
                            link_data[endpoint][direction];
                        router_in_vc[neighbor_of(endpoint, direction)][neighbor_input_port(direction)] =
                            link_vc[endpoint][direction];
                    end
                end
            end
        end
    end

    always_comb begin
        router_out_ready = '0;
        link_accept_raw = '0;
        link_can_load = '0;
        completion_valid_raw = '0;
        completion_tag_raw = '0;
        eject_advance_raw = '0;
        eject_head_raw = '0;
        stat_transfer = '0;
        stat_packet_head = '0;
        stat_no_credit = '0;
        stat_contended = '0;
        link_credit_consume = '0;

        for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
            stat_transfer[endpoint] = source_valid[endpoint] &&
                source_ready[endpoint][source_vc[endpoint]];
            stat_packet_head[endpoint] = source_data[endpoint][TAG_WIDTH+DEST_BITS];
            stat_no_credit[endpoint] = source_valid[endpoint] &&
                !source_ready[endpoint][source_vc[endpoint]];
            stat_contended[endpoint] = source_contended[endpoint];
            for (int direction = 0; direction < DIRS; direction++) begin
                if (has_neighbor(endpoint, direction) && link_valid[endpoint][direction]) begin
                    if (!link_final[endpoint][direction]) begin
                        link_accept_raw[endpoint][direction] = 1'b1;
                    end
                end
            end
        end

        for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
            if (eject_grant_valid[endpoint]) begin
                int source_endpoint;
                int source_direction;
                case (eject_grant_index[endpoint])
                    `NOC_DIR_NORTH: begin source_endpoint = endpoint + COLS; source_direction = `NOC_DIR_NORTH; end
                    `NOC_DIR_EAST:  begin source_endpoint = endpoint - 1;    source_direction = `NOC_DIR_EAST;  end
                    `NOC_DIR_SOUTH: begin source_endpoint = endpoint - COLS; source_direction = `NOC_DIR_SOUTH; end
                    default:        begin source_endpoint = endpoint + 1;    source_direction = `NOC_DIR_WEST;  end
                endcase
                completion_tag_raw[endpoint] = link_data[source_endpoint][source_direction][TAG_WIDTH-1:0];
                completion_valid_raw[endpoint] =
                    link_data[source_endpoint][source_direction][TAG_WIDTH+DEST_BITS+1];
                eject_advance_raw[endpoint] = !completion_valid_raw[endpoint] || completion_ready[endpoint];
                link_accept_raw[source_endpoint][source_direction] = eject_advance_raw[endpoint];
                eject_head_raw[endpoint] =
                    link_data[source_endpoint][source_direction][TAG_WIDTH+DEST_BITS];
            end
            stat_packet_head[EJECTION_BASE + endpoint] = eject_head[endpoint];
            stat_transfer[EJECTION_BASE + endpoint] = eject_grant_valid[endpoint] && eject_advance[endpoint];
            stat_no_credit[EJECTION_BASE + endpoint] = completion_valid[endpoint] &&
                !completion_ready[endpoint];
            stat_contended[EJECTION_BASE + endpoint] =
                |(eject_request[endpoint] & (eject_request[endpoint] - 1'b1));
        end

        for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
            for (int direction = 0; direction < DIRS; direction++) begin
                if (has_neighbor(endpoint, direction)) begin
                    int stat_id;
                    stat_id = INTERNAL_BASE + compact_internal_id(endpoint, direction);
                    link_can_load[endpoint][direction] = !link_valid[endpoint][direction] ||
                        link_accept[endpoint][direction];
                    router_out_ready[endpoint][direction] = link_can_load[endpoint][direction];
                    stat_transfer[stat_id] = router_out_valid[endpoint][direction] &&
                        router_out_ready[endpoint][direction];
                    stat_packet_head[stat_id] = router_out_data[endpoint][direction][TAG_WIDTH+DEST_BITS];
                    stat_no_credit[stat_id] = router_requested[endpoint][direction] &&
                        !stat_transfer[stat_id];
                    stat_contended[stat_id] = router_contended[endpoint][direction];
                    if (stat_transfer[stat_id]) begin
                        link_credit_consume[endpoint][direction][router_out_vc[endpoint][direction]] = 1'b1;
                    end
                end
            end
        end
    end

    assign network_idle = (&source_idle) && (&router_idle) && !(|link_valid);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            link_valid <= '0;
            link_data <= '0;
            link_vc <= '0;
            for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
                for (int direction = 0; direction < DIRS; direction++) begin
                    for (int vc = 0; vc < VC_NUM; vc++) begin
                        link_credit[endpoint][direction][vc] <= CREDIT_BITS'(BUFFER_DEPTH);
                    end
                end
            end
        end else if (model_step) begin
            for (int endpoint = 0; endpoint < ENDPOINTS; endpoint++) begin
                for (int direction = 0; direction < DIRS; direction++) begin
                    if (has_neighbor(endpoint, direction) && link_can_load[endpoint][direction]) begin
                        link_valid[endpoint][direction] <= router_out_valid[endpoint][direction];
                        if (router_out_valid[endpoint][direction]) begin
                            link_data[endpoint][direction] <= router_out_data[endpoint][direction];
                            link_vc[endpoint][direction] <= router_out_vc[endpoint][direction];
                        end
                    end
                    for (int vc = 0; vc < VC_NUM; vc++) begin
                        case ({link_credit_return[endpoint][direction][vc],
                               link_credit_consume[endpoint][direction][vc]})
                            2'b10: link_credit[endpoint][direction][vc] <=
                                link_credit[endpoint][direction][vc] + 1'b1;
                            2'b01: link_credit[endpoint][direction][vc] <=
                                link_credit[endpoint][direction][vc] - 1'b1;
                            default: link_credit[endpoint][direction][vc] <=
                                link_credit[endpoint][direction][vc];
                        endcase
                    end
                end
            end
        end
    end

endmodule
