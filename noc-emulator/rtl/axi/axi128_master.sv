module axi128_master #(
    parameter int unsigned ADDR_WIDTH = 64,
    parameter int unsigned ID_WIDTH = 4,
    parameter int unsigned MAX_BURST_BEATS = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      rd_cmd_valid,
    output logic                      rd_cmd_ready,
    input  logic [ADDR_WIDTH-1:0]     rd_cmd_addr,
    input  logic [4:0]                rd_cmd_beats,
    output logic                      rd_data_valid,
    input  logic                      rd_data_ready,
    output logic [127:0]              rd_data,
    output logic                      rd_data_last,
    output logic                      rd_error,
    output logic                      rd_error_rlast,
    output logic [1:0]                rd_error_resp,

    input  logic                      wr_cmd_valid,
    output logic                      wr_cmd_ready,
    input  logic [ADDR_WIDTH-1:0]     wr_cmd_addr,
    input  logic [4:0]                wr_cmd_beats,
    input  logic                      wr_data_valid,
    output logic                      wr_data_ready,
    input  logic [127:0]              wr_data,
    input  logic [15:0]               wr_data_strb,
    output logic                      wr_done,
    output logic                      wr_error,
    output logic [1:0]                wr_error_resp,

    output logic [ID_WIDTH-1:0]       m_axi_awid,
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awlock,
    output logic [3:0]                m_axi_awcache,
    output logic [2:0]                m_axi_awprot,
    output logic [3:0]                m_axi_awqos,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [127:0]              m_axi_wdata,
    output logic [15:0]               m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [ID_WIDTH-1:0]       m_axi_bid,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    output logic [ID_WIDTH-1:0]       m_axi_arid,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arlock,
    output logic [3:0]                m_axi_arcache,
    output logic [2:0]                m_axi_arprot,
    output logic [3:0]                m_axi_arqos,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [ID_WIDTH-1:0]       m_axi_rid,
    input  logic [127:0]              m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);
    logic read_address_pending;
    logic read_active;
    logic read_discard;
    logic [4:0] read_burst_beats;
    logic [4:0] read_burst_index;
    logic [4:0] read_remaining_beats;
    logic [ADDR_WIDTH-1:0] read_next_address;
    logic read_buffer_valid;
    logic read_buffer_last;
    logic [127:0] read_buffer_data;
    logic write_address_pending;
    logic write_active;
    logic write_response_pending;
    logic [4:0] write_burst_beats;
    logic [4:0] write_burst_index;
    logic [4:0] write_remaining_beats;
    logic [ADDR_WIDTH-1:0] write_next_address;

    function automatic logic command_valid(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [4:0] beats
    );
        begin
            command_valid = beats >= 1 && beats <= MAX_BURST_BEATS &&
                address[3:0] == 0;
        end
    endfunction

    function automatic logic [4:0] first_burst_beats(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [4:0] beats
    );
        logic [8:0] beats_to_boundary;
        begin
            beats_to_boundary = (13'h1000 - {1'b0, address[11:0]}) >> 4;
            if ({4'b0, beats} <= beats_to_boundary) first_burst_beats = beats;
            else first_burst_beats = beats_to_boundary[4:0];
        end
    endfunction

    assign rd_cmd_ready = !read_address_pending && !read_active && !read_buffer_valid;
    assign rd_data_valid = read_buffer_valid;
    assign rd_data = read_buffer_data;
    assign rd_data_last = read_buffer_last;
    assign m_axi_rready = read_active &&
        (read_discard || !read_buffer_valid || rd_data_ready);

    assign wr_cmd_ready = !write_address_pending && !write_active && !write_response_pending;
    assign wr_data_ready = write_active && m_axi_wready;
    assign m_axi_wvalid = write_active && wr_data_valid;
    assign m_axi_wdata = wr_data;
    assign m_axi_wstrb = wr_data_strb;
    assign m_axi_wlast = write_active &&
        write_burst_index + 1'b1 == write_burst_beats;
    assign m_axi_bready = write_response_pending;

    assign m_axi_awid = '0;
    assign m_axi_awlen = write_burst_beats - 1'b1;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awqos = 4'b0000;
    assign m_axi_awvalid = write_address_pending;

    assign m_axi_arid = '0;
    assign m_axi_arlen = read_burst_beats - 1'b1;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arqos = 4'b0000;
    assign m_axi_arvalid = read_address_pending;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_address_pending <= 1'b0;
            read_active <= 1'b0;
            read_discard <= 1'b0;
            read_burst_beats <= '0;
            read_burst_index <= '0;
            read_remaining_beats <= '0;
            read_next_address <= '0;
            read_buffer_valid <= 1'b0;
            read_buffer_last <= 1'b0;
            read_buffer_data <= '0;
            m_axi_araddr <= '0;
            rd_error <= 1'b0;
            rd_error_rlast <= 1'b0;
            rd_error_resp <= '0;
        end else begin
            rd_error <= 1'b0;
            rd_error_rlast <= 1'b0;
            if (read_buffer_valid && rd_data_ready) read_buffer_valid <= 1'b0;
            if (rd_cmd_valid && rd_cmd_ready) begin
                if (!command_valid(rd_cmd_addr, rd_cmd_beats)) begin
                    rd_error <= 1'b1;
                    rd_error_resp <= 2'b11;
                end else begin
                    m_axi_araddr <= rd_cmd_addr;
                    read_burst_beats <= first_burst_beats(rd_cmd_addr, rd_cmd_beats);
                    read_burst_index <= '0;
                    read_remaining_beats <= rd_cmd_beats -
                        first_burst_beats(rd_cmd_addr, rd_cmd_beats);
                    read_next_address <= rd_cmd_addr +
                        (first_burst_beats(rd_cmd_addr, rd_cmd_beats) << 4);
                    read_address_pending <= 1'b1;
                end
            end
            if (read_address_pending && m_axi_arready) begin
                read_address_pending <= 1'b0;
                read_active <= 1'b1;
            end
            if (read_active && m_axi_rvalid && m_axi_rready) begin
                logic expected_last;
                expected_last = read_burst_index + 1'b1 == read_burst_beats;
                if (read_discard) begin
                    if (m_axi_rlast) begin
                        read_active <= 1'b0;
                        read_discard <= 1'b0;
                    end
                end else if (m_axi_rresp != 2'b00) begin
                    rd_error <= 1'b1;
                    rd_error_resp <= m_axi_rresp;
                    read_buffer_valid <= 1'b0;
                    if (m_axi_rlast) read_active <= 1'b0;
                    else read_discard <= 1'b1;
                end else if (m_axi_rlast != expected_last) begin
                    rd_error <= 1'b1;
                    rd_error_resp <= 2'b11;
                    rd_error_rlast <= 1'b1;
                    read_buffer_valid <= 1'b0;
                    read_active <= 1'b0;
                end else begin
                    read_buffer_valid <= 1'b1;
                    read_buffer_data <= m_axi_rdata;
                    read_buffer_last <= expected_last && read_remaining_beats == 0;
                    if (expected_last && read_remaining_beats != 0) begin
                        m_axi_araddr <= read_next_address;
                        read_burst_beats <= read_remaining_beats;
                        read_burst_index <= '0;
                        read_next_address <= read_next_address + (read_remaining_beats << 4);
                        read_remaining_beats <= '0;
                        read_active <= 1'b0;
                        read_address_pending <= 1'b1;
                    end else if (expected_last) begin
                        read_active <= 1'b0;
                    end else begin
                        read_burst_index <= read_burst_index + 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            write_address_pending <= 1'b0;
            write_active <= 1'b0;
            write_response_pending <= 1'b0;
            write_burst_beats <= '0;
            write_burst_index <= '0;
            write_remaining_beats <= '0;
            write_next_address <= '0;
            m_axi_awaddr <= '0;
            wr_done <= 1'b0;
            wr_error <= 1'b0;
            wr_error_resp <= '0;
        end else begin
            wr_done <= 1'b0;
            wr_error <= 1'b0;
            if (wr_cmd_valid && wr_cmd_ready) begin
                if (!command_valid(wr_cmd_addr, wr_cmd_beats)) begin
                    wr_error <= 1'b1;
                    wr_error_resp <= 2'b11;
                end else begin
                    m_axi_awaddr <= wr_cmd_addr;
                    write_burst_beats <= first_burst_beats(wr_cmd_addr, wr_cmd_beats);
                    write_burst_index <= '0;
                    write_remaining_beats <= wr_cmd_beats -
                        first_burst_beats(wr_cmd_addr, wr_cmd_beats);
                    write_next_address <= wr_cmd_addr +
                        (first_burst_beats(wr_cmd_addr, wr_cmd_beats) << 4);
                    write_address_pending <= 1'b1;
                end
            end
            if (write_address_pending && m_axi_awready) begin
                write_address_pending <= 1'b0;
                write_active <= 1'b1;
            end
            if (write_active && wr_data_valid && m_axi_wready) begin
                if (write_burst_index + 1'b1 == write_burst_beats) begin
                    write_active <= 1'b0;
                    write_response_pending <= 1'b1;
                end else begin
                    write_burst_index <= write_burst_index + 1'b1;
                end
            end
            if (write_response_pending && m_axi_bvalid) begin
                write_response_pending <= 1'b0;
                if (m_axi_bresp != 2'b00) begin
                    wr_error <= 1'b1;
                    wr_error_resp <= m_axi_bresp;
                end else if (write_remaining_beats != 0) begin
                    m_axi_awaddr <= write_next_address;
                    write_burst_beats <= write_remaining_beats;
                    write_burst_index <= '0;
                    write_next_address <= write_next_address + (write_remaining_beats << 4);
                    write_remaining_beats <= '0;
                    write_address_pending <= 1'b1;
                end else begin
                    wr_done <= 1'b1;
                end
            end
        end
    end

endmodule
