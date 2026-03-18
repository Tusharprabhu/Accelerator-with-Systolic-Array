//============================================================================
// Module: Input Buffer (BRAM-style)
// Description: Stores input matrix data and feeds it to the systolic array
//              with proper staggered timing (skewing) for correct systolic
//              data flow. Implements double-buffering concept.
//
//              For matrix A (row-fed): Row i is delayed by i cycles
//              For matrix B (col-fed): Col j is delayed by j cycles
//
// Parameters:
//   ARRAY_SIZE - Dimension N of the systolic array
//   DATA_WIDTH - Bit width of each element
//   DEPTH      - Number of elements per row/column to store
//
// Author: AI Accelerator Project
//============================================================================

module input_buffer #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 4    // K dimension (inner dimension of matmul)
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Write interface
    input  wire                                wr_en,
    input  wire [$clog2(ARRAY_SIZE)-1:0]       wr_row,    // Which row/col to write
    input  wire [$clog2(DEPTH)-1:0]            wr_col,    // Position within row/col
    input  wire [DATA_WIDTH-1:0]               wr_data,
    
    // Read interface (staggered output for systolic feeding)
    input  wire                                rd_en,
    input  wire                                rd_start,  // Pulse to start reading
    output reg  [ARRAY_SIZE*DATA_WIDTH-1:0]    rd_data,   // One element per row/col
    output reg                                 rd_valid
);

    //------------------------------------------------------------------------
    // Storage: ARRAY_SIZE rows × DEPTH columns
    //------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:ARRAY_SIZE-1][0:DEPTH-1];
    
    //------------------------------------------------------------------------
    // Read counter and skew logic
    //------------------------------------------------------------------------
    reg [$clog2(DEPTH + ARRAY_SIZE)-1:0] cycle_count;
    reg                                   active;
    reg                                   rd_start_d;  // Delayed version for edge detection
    
    // Total cycles needed: DEPTH + ARRAY_SIZE - 1 (for staggered feeding)
    localparam TOTAL_CYCLES = DEPTH + ARRAY_SIZE - 1;
    
    integer idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            active      <= 1'b0;
            rd_valid    <= 1'b0;
            rd_data     <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
            rd_start_d  <= 1'b0;
        end else begin
            // Delay rd_start for edge detection
            rd_start_d <= rd_start;
            
            // Write logic
            if (wr_en) begin
                mem[wr_row][wr_col] <= wr_data;
            end
            
            // Read state machine - detect rising edge of rd_start
            if (rd_start && !rd_start_d) begin  // Rising edge detection
                cycle_count <= 0;
                active      <= 1'b1;
                rd_valid    <= 1'b0;
            end else if (active && rd_en) begin
                if (cycle_count < TOTAL_CYCLES) begin
                    rd_valid <= 1'b1;
                    cycle_count <= cycle_count + 1;
                end else begin
                    active   <= 1'b0;
                    rd_valid <= 1'b0;
                end
            end
            
            // Generate staggered (skewed) output
            // Row i gets data delayed by i cycles
            if (active && rd_en) begin
                for (idx = 0; idx < ARRAY_SIZE; idx = idx + 1) begin
                    // Effective index for row idx at current cycle
                    // Row i starts reading at cycle i (skew)
                    if ((cycle_count >= idx) && 
                        (cycle_count - idx < DEPTH)) begin
                        rd_data[idx*DATA_WIDTH +: DATA_WIDTH] <= 
                            mem[idx][cycle_count - idx];
                    end else begin
                        rd_data[idx*DATA_WIDTH +: DATA_WIDTH] <= 
                            {DATA_WIDTH{1'b0}};
                    end
                end
            end
        end
    end

endmodule
