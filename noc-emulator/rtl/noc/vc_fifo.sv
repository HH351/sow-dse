module vc_fifo #(
    parameter int unsigned WIDTH = 22,
    parameter int unsigned DEPTH = 8,
    localparam int unsigned COUNT_W = $clog2(DEPTH + 1)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 model_step,
    input  logic                 push,
    input  logic [WIDTH-1:0]     push_data,
    input  logic                 pop,
    output logic [WIDTH-1:0]     front_data,
    output logic                 empty,
    output logic                 full,
    output logic [COUNT_W-1:0]   count
);
    (* shreg_extract = "yes", srl_style = "srl" *)
    logic [DEPTH-1:0] storage [WIDTH-1:0];

    assign empty = (count == 0);
    assign full = (count == DEPTH);

    always_comb begin
        // Data is only consumed when nonempty. An empty FIFO exposes stale data.
        for (int bit_index = 0; bit_index < WIDTH; bit_index++) begin
            front_data[bit_index] = storage[bit_index][$clog2(DEPTH)'(count - 1'b1)];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= '0;
        end else if (model_step) begin
            if (push) begin
                for (int bit_index = 0; bit_index < WIDTH; bit_index++) begin
                    storage[bit_index] <= {storage[bit_index][DEPTH-2:0], push_data[bit_index]};
                end
            end
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
