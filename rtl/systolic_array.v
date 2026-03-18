//============================================================================
// Module: Systolic Array (NxN)
// Description: NxN grid of Processing Elements for matrix multiplication.
//              Implements C = A × B where:
//                - A flows horizontally (left → right)
//                - B flows vertically (top → bottom)
//              Each PE computes: acc += a * b (MAC operation)
//
// Data Flow Pattern (4x4 example, staggered input):
//   Cycle 0: A[0][0] enters PE(0,0), B[0][0] enters PE(0,0)
//   Cycle 1: A[0][1] enters PE(0,0), A[0][0] propagates to PE(0,1)
//   ...and so on (wave-like computation)
//
// Parameters:
//   ARRAY_SIZE - Dimension N of the NxN array (default: 4)
//   DATA_WIDTH - Bit width of input operands (default: 8)
//   ACC_WIDTH  - Bit width of accumulator (default: 32)
//
// Author: AI Accelerator Project
//============================================================================

module systolic_array #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                                     clk,
    input  wire                                     rst_n,
    input  wire                                     en,
    input  wire                                     clear_acc,
    
    // A inputs: one per row (fed from the left)
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]         a_in,
    // B inputs: one per column (fed from the top)
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]         b_in,
    
    // Accumulated results: NxN matrix of ACC_WIDTH each
    output wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] result
);

    //------------------------------------------------------------------------
    // Internal wires for inter-PE connections
    //------------------------------------------------------------------------
    // Horizontal wires: a propagates right through columns
    // Wire [row][col] connects PE(row,col).a_out → PE(row,col+1).a_in
    wire [DATA_WIDTH-1:0] a_wire [0:ARRAY_SIZE-1][0:ARRAY_SIZE];
    
    // Vertical wires: b propagates down through rows
    // Wire [row][col] connects PE(row,col).b_out → PE(row+1,col).b_in
    wire [DATA_WIDTH-1:0] b_wire [0:ARRAY_SIZE][0:ARRAY_SIZE-1];
    
    // Accumulator outputs from each PE
    wire [ACC_WIDTH-1:0]  acc_wire [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    //------------------------------------------------------------------------
    // Connect external inputs to the boundary wires
    //------------------------------------------------------------------------
    genvar i, j;
    
    // A inputs connect to leftmost column (col=0 input)
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : gen_a_input
            assign a_wire[i][0] = a_in[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    // B inputs connect to topmost row (row=0 input)
    generate
        for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : gen_b_input
            assign b_wire[0][j] = b_in[j*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate

    //------------------------------------------------------------------------
    // Instantiate NxN PE grid
    //------------------------------------------------------------------------
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : gen_row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : gen_col
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .en        (en),
                    .clear_acc (clear_acc),
                    .a_in      (a_wire[i][j]),
                    .b_in      (b_wire[i][j]),
                    .a_out     (a_wire[i][j+1]),
                    .b_out     (b_wire[i+1][j]),
                    .acc       (acc_wire[i][j])
                );
            end
        end
    endgenerate

    //------------------------------------------------------------------------
    // Map internal accumulator wires to flat output bus
    // result[(i*ARRAY_SIZE + j)*ACC_WIDTH +: ACC_WIDTH] = acc_wire[i][j]
    //------------------------------------------------------------------------
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : gen_result_row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : gen_result_col
                assign result[(i*ARRAY_SIZE + j)*ACC_WIDTH +: ACC_WIDTH] = acc_wire[i][j];
            end
        end
    endgenerate

endmodule
