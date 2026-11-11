module tag_pool #(
    parameter int unsigned CAPACITY = 256,
    localparam int unsigned TAG_WIDTH = (CAPACITY <= 2) ? 1 : $clog2(CAPACITY),
    localparam int unsigned FRESH_COUNT_WIDTH = (CAPACITY <= 1) ? 1 : $clog2(CAPACITY + 1)
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    allocate,
    output logic                    allocate_ready,
    output logic [TAG_WIDTH-1:0]    allocated_tag,
    input  logic                    release_valid,
    input  logic [TAG_WIDTH-1:0]    released_tag,
    output logic [TAG_WIDTH:0]      free_count
);
    (* ram_style = "block" *) logic [TAG_WIDTH-1:0] recycle_memory [0:CAPACITY-1];
    logic [FRESH_COUNT_WIDTH-1:0] next_fresh;
    logic [TAG_WIDTH-1:0] read_pointer;
    logic [TAG_WIDTH-1:0] write_pointer;
    logic [TAG_WIDTH:0] tail_count;
    logic recycle_head_valid;
    logic [TAG_WIDTH-1:0] recycle_head;
    logic refill_pending;
    logic [TAG_WIDTH-1:0] recycle_read_data;
    logic use_recycled;
    logic use_fresh;
    logic use_release_bypass;
    logic allocation_fire;
    logic start_refill;
    logic release_to_memory;
    logic release_to_head;

    assign use_recycled = recycle_head_valid;
    assign use_fresh = !recycle_head_valid && next_fresh < CAPACITY;
    assign use_release_bypass = !recycle_head_valid && !refill_pending &&
        next_fresh >= CAPACITY && release_valid;
    assign allocate_ready = use_recycled || use_fresh || use_release_bypass;
    assign allocated_tag = use_recycled ? recycle_head :
        (use_fresh ? TAG_WIDTH'(next_fresh) : released_tag);
    assign allocation_fire = allocate && allocate_ready;
    assign start_refill = recycle_head_valid && allocation_fire && tail_count != 0;
    assign release_to_memory = release_valid && (refill_pending ||
        (recycle_head_valid && !(allocation_fire && tail_count == 0)));
    assign release_to_head = release_valid && !refill_pending &&
        ((!recycle_head_valid && !(allocation_fire && use_release_bypass)) ||
        (recycle_head_valid && allocation_fire && tail_count == 0));

    // A synchronous simple dual-port template keeps the recycled-tag queue in
    // BRAM. Refill latency is physical time only; allocate_ready stalls while
    // the cached head is being loaded, so logical model time never advances.
    always_ff @(posedge clk) begin
        if (release_to_memory) recycle_memory[write_pointer] <= released_tag;
        if (start_refill) recycle_read_data <= recycle_memory[read_pointer];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            next_fresh <= '0;
            read_pointer <= '0;
            write_pointer <= '0;
            tail_count <= '0;
            recycle_head_valid <= 1'b0;
            recycle_head <= '0;
            refill_pending <= 1'b0;
            free_count <= (TAG_WIDTH + 1)'(CAPACITY);
        end else begin
            if (allocation_fire && use_fresh) begin
                next_fresh <= next_fresh + 1'b1;
            end

            if (refill_pending) begin
                recycle_head <= recycle_read_data;
                recycle_head_valid <= 1'b1;
                refill_pending <= 1'b0;
            end else if (start_refill) begin
                recycle_head_valid <= 1'b0;
                refill_pending <= 1'b1;
            end else if (release_to_head) begin
                recycle_head <= released_tag;
                recycle_head_valid <= 1'b1;
            end else if (recycle_head_valid && allocation_fire) begin
                recycle_head_valid <= 1'b0;
            end

            if (start_refill) begin
                read_pointer <= (read_pointer == CAPACITY - 1) ?
                    '0 : read_pointer + 1'b1;
            end
            if (release_to_memory) begin
                write_pointer <= (write_pointer == CAPACITY - 1) ?
                    '0 : write_pointer + 1'b1;
            end
            case ({release_to_memory, start_refill})
                2'b10: tail_count <= tail_count + 1'b1;
                2'b01: tail_count <= tail_count - 1'b1;
                default: tail_count <= tail_count;
            endcase

            case ({allocation_fire, release_valid})
                2'b10: free_count <= free_count - 1'b1;
                2'b01: free_count <= free_count + 1'b1;
                default: free_count <= free_count;
            endcase
        end
    end

endmodule
