module link_stats_bank #(
    parameter int unsigned LINK_COUNT = 12,
    parameter int unsigned COUNTER_BITS = 32,
    parameter int unsigned EPOCH_MARGIN = (COUNTER_BITS > 16) ? 32'd65535 : 1,
    parameter logic [COUNTER_BITS-1:0] EPOCH_THRESHOLD =
        {COUNTER_BITS{1'b1}} - COUNTER_BITS'(EPOCH_MARGIN)
) (
    input  logic                                  clk,
    input  logic                                  rst_n,
    input  logic                                  model_step,
    input  logic                                  clear_epoch,
    input  logic [LINK_COUNT-1:0]                 transfer,
    input  logic [LINK_COUNT-1:0]                 packet_head,
    input  logic [LINK_COUNT-1:0]                 no_credit,
    input  logic [LINK_COUNT-1:0]                 contended,
    output logic                                  epoch_needed,
    output logic                                  pipeline_idle,
    output logic [LINK_COUNT-1:0][COUNTER_BITS-1:0] flit_count,
    output logic [LINK_COUNT-1:0][COUNTER_BITS-1:0] head_count,
    output logic [LINK_COUNT-1:0][COUNTER_BITS-1:0] blocked_count,
    output logic [LINK_COUNT-1:0][COUNTER_BITS-1:0] contended_count
);
    logic                                         sample_valid;
    logic [LINK_COUNT-1:0]                        sampled_transfer;
    logic [LINK_COUNT-1:0]                        sampled_packet_head;
    logic [LINK_COUNT-1:0]                        sampled_no_credit;
    logic [LINK_COUNT-1:0]                        sampled_contended;
    logic                                         threshold_hit;

    assign pipeline_idle = !sample_valid;

    always_comb begin
        threshold_hit = 1'b0;
        for (int link = 0; link < LINK_COUNT; link++) begin
            // Wide counters have ample drain margin; small verification counters
            // must pre-trigger to avoid wrapping while the sample pipeline drains.
            if (COUNTER_BITS > 16) begin
                threshold_hit |= flit_count[link] >= EPOCH_THRESHOLD ||
                    head_count[link] >= EPOCH_THRESHOLD ||
                    blocked_count[link] >= EPOCH_THRESHOLD ||
                    contended_count[link] >= EPOCH_THRESHOLD;
            end else begin
                threshold_hit |=
                    (sampled_transfer[link] && flit_count[link] >= EPOCH_THRESHOLD - 1'b1) ||
                    (sampled_transfer[link] && sampled_packet_head[link] &&
                        head_count[link] >= EPOCH_THRESHOLD - 1'b1) ||
                    (sampled_no_credit[link] && blocked_count[link] >= EPOCH_THRESHOLD - 1'b1) ||
                    (sampled_contended[link] && contended_count[link] >= EPOCH_THRESHOLD - 1'b1);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || clear_epoch) begin
            sample_valid <= 1'b0;
            sampled_transfer <= '0;
            sampled_packet_head <= '0;
            sampled_no_credit <= '0;
            sampled_contended <= '0;
            epoch_needed <= 1'b0;
            for (int link = 0; link < LINK_COUNT; link++) begin
                flit_count[link] <= '0;
                head_count[link] <= '0;
                blocked_count[link] <= '0;
                contended_count[link] <= '0;
            end
        end else begin
            sample_valid <= model_step;
            epoch_needed <= epoch_needed || threshold_hit;
            if (model_step) begin
                sampled_transfer <= transfer;
                sampled_packet_head <= packet_head;
                sampled_no_credit <= no_credit;
                sampled_contended <= contended;
            end
            if (sample_valid) begin
                for (int link = 0; link < LINK_COUNT; link++) begin
                    flit_count[link] <= flit_count[link] + sampled_transfer[link];
                    head_count[link] <= head_count[link] +
                        (sampled_transfer[link] && sampled_packet_head[link]);
                    blocked_count[link] <= blocked_count[link] + sampled_no_credit[link];
                    contended_count[link] <= contended_count[link] + sampled_contended[link];
                end
            end
        end
    end

endmodule
