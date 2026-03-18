//============================================================================
// Module: Output Buffer
// Description: Collects accumulated results from the systolic array and
//              provides a read interface for the host/controller.
//              Stores the NxN result matrix C.
//
// Parameters:
//   ARRAY_SIZE - Dimension N of the systolic array
//   ACC_WIDTH  - Bit width of each accumulated result
//
// Author: AI Accelerator Project
//============================================================================

module output_buffer #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 32
)(
    input  wire                                          clk,
    input  wire                                          rst_n,
    
    // Write interface (from systolic array)
    input  wire                                          wr_en,
    input  wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0]    wr_data,  // Full result matrix
    
    // Read interface (to host/external)
    input  wire                                          rd_en,
    input  wire [$clog2(ARRAY_SIZE)-1:0]                 rd_row,
    input  wire [$clog2(ARRAY_SIZE)-1:0]                 rd_col,
    output reg  [ACC_WIDTH-1:0]                          rd_data,
    output reg                                           rd_valid,
    
    // Status
    output reg                                           buf_ready  // Data available
);

    //------------------------------------------------------------------------
    // Storage: NxN result matrix
    //------------------------------------------------------------------------
    reg [ACC_WIDTH-1:0] result_mem [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data   <= {ACC_WIDTH{1'b0}};
            rd_valid  <= 1'b0;
            buf_ready <= 1'b0;
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    result_mem[i][j] <= {ACC_WIDTH{1'b0}};
                end
            end
        end else begin
            // Write: capture full result matrix from systolic array
            if (wr_en) begin
                for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                    for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                        result_mem[i][j] <= 
                            wr_data[(i*ARRAY_SIZE + j)*ACC_WIDTH +: ACC_WIDTH];
                    end
                end
                buf_ready <= 1'b1;
            end
            
            // Read: output selected element
            if (rd_en && buf_ready) begin
                rd_data  <= result_mem[rd_row][rd_col];
                rd_valid <= 1'b1;
            end else begin
                rd_valid <= 1'b0;
            end
        end
    end

endmodule
