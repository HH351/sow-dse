// DDR command, routing, state and error constants.
package noc_emulator_protocol_pkg;
    localparam logic [63:0] CONTROL_MAGIC = 64'h314c554d45434f4e;
    localparam logic [31:0] COMMAND_BYTES = 32'd16;
    localparam logic [31:0] ROUTING_DOR = 32'd0;
    localparam logic [31:0] ROUTING_VALIANT = 32'd1;
    localparam logic [15:0] STATE_IDLE = 16'd1;
    localparam logic [15:0] STATE_RUNNING = 16'd2;
    localparam logic [15:0] STATE_DONE = 16'd3;
    localparam logic [15:0] STATE_ERROR = 16'd4;
    localparam logic [15:0] ERR_BAD_MAGIC = 16'd1;
    localparam logic [15:0] ERR_BAD_ROUTING = 16'd2;
    localparam logic [15:0] ERR_BAD_RANGE = 16'd5;
    localparam logic [15:0] ERR_AXI_READ = 16'd8;
    localparam logic [15:0] ERR_AXI_WRITE = 16'd9;
    localparam logic [15:0] ERR_AXI_RLAST = 16'd10;
    localparam logic [15:0] ERR_INTERNAL = 16'd11;
endpackage
