//============================================================================
// Module: Processing Element (PE)
// Description: Fundamental MAC (Multiply-Accumulate) unit for systolic array.
//              Each PE performs: acc += a_in * b_in
//              Data flows: a_in → a_out (right), b_in → b_out (down)
//
// Parameters:
//   DATA_WIDTH - Bit width of input operands (default: 8 for INT8)
//   ACC_WIDTH  - Bit width of accumulator (default: 32)
//
// Author: AI Accelerator Project
//============================================================================

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,      // Active-low reset
    input  wire                    en,         // Enable signal
    input  wire                    clear_acc,  // Clear accumulator
    input  wire [DATA_WIDTH-1:0]   a_in,       // Input from left
    input  wire [DATA_WIDTH-1:0]   b_in,       // Input from top
    output reg  [DATA_WIDTH-1:0]   a_out,      // Output to right
    output reg  [DATA_WIDTH-1:0]   b_out,      // Output to bottom
    output reg  [ACC_WIDTH-1:0]    acc          // Accumulated result
);

    // Internal product wire
    wire [2*DATA_WIDTH-1:0] product;
    
    // Multiply: a_in * b_in (unsigned multiplication)
    assign product = a_in * b_in;

    // Sequential logic: MAC operation + data forwarding
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {DATA_WIDTH{1'b0}};
            b_out <= {DATA_WIDTH{1'b0}};
            acc   <= {ACC_WIDTH{1'b0}};
        end else if (clear_acc) begin
            acc   <= {ACC_WIDTH{1'b0}};
            a_out <= {DATA_WIDTH{1'b0}};
            b_out <= {DATA_WIDTH{1'b0}};
        end else if (en) begin
            // MAC: accumulate product (sign-extend for proper width)
            acc   <= acc + {{(ACC_WIDTH-2*DATA_WIDTH){1'b0}}, product};
            // Forward data to neighbors
            a_out <= a_in;  // Pass A to the right
            b_out <= b_in;  // Pass B downward
        end
    end

endmodule
