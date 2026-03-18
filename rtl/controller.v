//============================================================================
// Module: Controller FSM
// Description: Master controller for the systolic array accelerator.
//              Manages the computation pipeline through states:
//              IDLE → LOAD_A → LOAD_B → COMPUTE → STORE → DONE
//
//              Supports tiling for large matrices:
//              - Breaks NxN computation into TILE_SIZE x TILE_SIZE tiles
//              - Iterates over tiles along K dimension
//              - Accumulates partial results across tiles
//
// Parameters:
//   ARRAY_SIZE - Dimension N of the systolic array
//   DATA_WIDTH - Bit width of input operands
//   TILE_SIZE  - Size of each tile (= ARRAY_SIZE for basic operation)
//   MAX_DIM    - Maximum supported matrix dimension
//
// Author: AI Accelerator Project
//============================================================================

module controller #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter TILE_SIZE  = 4,
    parameter MAX_DIM    = 16,
    parameter SKIP_LOAD  = 0  // Skip loading phase if data already in buffers
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Host interface
    input  wire                    start,          // Begin computation
    input  wire [$clog2(MAX_DIM):0] mat_dim,       // Actual matrix dimension
    output reg                     done,           // Computation complete
    output reg                     busy,           // Currently processing
    
    // Input buffer A control
    output reg                     buf_a_wr_en,
    output reg  [$clog2(ARRAY_SIZE)-1:0] buf_a_wr_row,
    output reg  [$clog2(TILE_SIZE)-1:0]  buf_a_wr_col,
    output reg                     buf_a_rd_en,
    output reg                     buf_a_rd_start,
    
    // Input buffer B control
    output reg                     buf_b_wr_en,
    output reg  [$clog2(ARRAY_SIZE)-1:0] buf_b_wr_row,
    output reg  [$clog2(TILE_SIZE)-1:0]  buf_b_wr_col,
    output reg                     buf_b_rd_en,
    output reg                     buf_b_rd_start,
    
    // Systolic array control
    output reg                     sa_en,          // Array enable
    output reg                     sa_clear_acc,   // Clear accumulators
    
    // Output buffer control
    output reg                     obuf_wr_en,     // Store results
    
    // Performance counters
    output reg  [31:0]             cycle_count,    // Total cycles
    output reg  [31:0]             compute_cycles, // Compute-only cycles
    output reg  [31:0]             total_macs      // Total MAC operations
);

    // Additional counter for SKIP_LOAD stabilization
    reg [$clog2(ARRAY_SIZE):0] skip_delay;
    
    //------------------------------------------------------------------------
    // FSM States
    //------------------------------------------------------------------------
    localparam [3:0] S_IDLE    = 4'd0,
                     S_INIT    = 4'd1,
                     S_LOAD_A  = 4'd2,
                     S_LOAD_B  = 4'd3,
                     S_FEED    = 4'd4,
                     S_COMPUTE = 4'd5,
                     S_DRAIN   = 4'd6,
                     S_STORE   = 4'd7,
                     S_TILE_NEXT = 4'd8,
                     S_DONE    = 4'd9;
    
    reg [3:0] state, next_state;
    
    //------------------------------------------------------------------------
    // Tiling counters
    //------------------------------------------------------------------------
    reg [$clog2(MAX_DIM):0] tile_row;    // Current tile row index
    reg [$clog2(MAX_DIM):0] tile_col;    // Current tile column index
    reg [$clog2(MAX_DIM):0] tile_k;      // Current tile K index
    reg [$clog2(MAX_DIM):0] num_tiles;   // Total tiles per dimension
    
    //------------------------------------------------------------------------
    // Internal counters
    //------------------------------------------------------------------------
    reg [$clog2(TILE_SIZE + ARRAY_SIZE):0] feed_count;
    reg [$clog2(TILE_SIZE + ARRAY_SIZE):0] compute_count;
    reg [$clog2(ARRAY_SIZE):0]             load_row_count;
    reg [$clog2(TILE_SIZE):0]              load_col_count;
    
    // Pipeline fill + drain time
    localparam FEED_CYCLES = TILE_SIZE + ARRAY_SIZE - 1;
    localparam DRAIN_CYCLES = ARRAY_SIZE;  // Extra cycles for pipeline drain
    
    //------------------------------------------------------------------------
    // FSM: State Register
    //------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    //------------------------------------------------------------------------
    // FSM: Next State Logic
    //------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_INIT;
            end
            
            S_INIT: begin
                // Skip loading if SKIP_LOAD is set (data already in buffers)
                if (SKIP_LOAD) begin
                    if (skip_delay >= 4)  // Wait more cycles for stabilization
                        next_state = S_FEED;
                    else
                        next_state = S_INIT;
                end else
                    next_state = S_LOAD_A;
            end
            
            // Additional cycle to let buffer signals stabilize
            S_LOAD_A: begin
                if (SKIP_LOAD)
                    next_state = S_FEED;
                else if (load_row_count == ARRAY_SIZE - 1 && 
                    load_col_count == TILE_SIZE - 1)
                    next_state = S_LOAD_B;
            end
            
            S_LOAD_B: begin
                if (load_row_count == ARRAY_SIZE - 1 && 
                    load_col_count == TILE_SIZE - 1)
                    next_state = S_FEED;
            end
            
            S_FEED: begin
                next_state = S_COMPUTE;
            end
            
            S_COMPUTE: begin
                if (compute_count >= FEED_CYCLES + DRAIN_CYCLES - 1)
                    next_state = S_DRAIN;
            end
            
            S_DRAIN: begin
                next_state = S_STORE;
            end
            
            S_STORE: begin
                next_state = S_TILE_NEXT;
            end
            
            S_TILE_NEXT: begin
                if (tile_k < num_tiles - 1)
                    next_state = S_LOAD_A;  // Next K tile
                else if (tile_col < num_tiles - 1) begin
                    next_state = S_LOAD_A;  // Next column tile
                end else if (tile_row < num_tiles - 1) begin
                    next_state = S_LOAD_A;  // Next row tile
                end else begin
                    next_state = S_DONE;    // All tiles complete
                end
            end
            
            S_DONE: begin
                next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end
    
    //------------------------------------------------------------------------
    // FSM: Output Logic & Counters
    //------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done            <= 1'b0;
            busy            <= 1'b0;
            buf_a_wr_en     <= 1'b0;
            buf_a_wr_row    <= 0;
            buf_a_wr_col    <= 0;
            buf_a_rd_en     <= 1'b0;
            buf_a_rd_start  <= 1'b0;
            buf_b_wr_en     <= 1'b0;
            buf_b_wr_row    <= 0;
            buf_b_wr_col    <= 0;
            buf_b_rd_en     <= 1'b0;
            buf_b_rd_start  <= 1'b0;
            sa_en           <= 1'b0;
            sa_clear_acc    <= 1'b0;
            obuf_wr_en      <= 1'b0;
            cycle_count     <= 32'd0;
            compute_cycles  <= 32'd0;
            total_macs      <= 32'd0;
            tile_row        <= 0;
            tile_col        <= 0;
            tile_k          <= 0;
            num_tiles       <= 0;
            feed_count      <= 0;
            compute_count   <= 0;
            load_row_count  <= 0;
            load_col_count  <= 0;
            skip_delay      <= 0;
        end else begin
            // Default de-assertions
            buf_a_wr_en    <= 1'b0;
            buf_b_wr_en    <= 1'b0;
            buf_a_rd_start <= 1'b0;
            buf_b_rd_start <= 1'b0;
            obuf_wr_en     <= 1'b0;
            sa_clear_acc   <= 1'b0;
            done           <= 1'b0;
            
            // Global cycle counter (when busy)
            if (busy)
                cycle_count <= cycle_count + 1;
            
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    sa_en <= 1'b0;
                end
                
                S_INIT: begin
                    busy           <= 1'b1;
                    cycle_count    <= 32'd0;
                    compute_cycles <= 32'd0;
                    total_macs     <= 32'd0;
                    tile_row       <= 0;
                    tile_col       <= 0;
                    tile_k         <= 0;
                    // Calculate number of tiles (ceiling division)
                    num_tiles      <= (mat_dim + TILE_SIZE - 1) / TILE_SIZE;
                    sa_clear_acc   <= 1'b1;  // Clear accumulators
                    load_row_count <= 0;
                    load_col_count <= 0;
                    
                    // When SKIP_LOAD, use skip_delay for stabilization
                    if (SKIP_LOAD) begin
                        if (skip_delay < 5)
                            skip_delay <= skip_delay + 1;
                    end else begin
                        skip_delay <= 0;
                    end
                end
                
                S_LOAD_A: begin
                    buf_a_wr_en  <= 1'b1;
                    buf_a_wr_row <= load_row_count[$clog2(ARRAY_SIZE)-1:0];
                    buf_a_wr_col <= load_col_count[$clog2(TILE_SIZE)-1:0];
                    
                    if (load_col_count == TILE_SIZE - 1) begin
                        load_col_count <= 0;
                        if (load_row_count == ARRAY_SIZE - 1) begin
                            load_row_count <= 0;
                        end else begin
                            load_row_count <= load_row_count + 1;
                        end
                    end else begin
                        load_col_count <= load_col_count + 1;
                    end
                end
                
                S_LOAD_B: begin
                    buf_b_wr_en  <= 1'b1;
                    buf_b_wr_row <= load_row_count[$clog2(ARRAY_SIZE)-1:0];
                    buf_b_wr_col <= load_col_count[$clog2(TILE_SIZE)-1:0];
                    
                    if (load_col_count == TILE_SIZE - 1) begin
                        load_col_count <= 0;
                        if (load_row_count == ARRAY_SIZE - 1) begin
                            load_row_count <= 0;
                        end else begin
                            load_row_count <= load_row_count + 1;
                        end
                    end else begin
                        load_col_count <= load_col_count + 1;
                    end
                end
                
                S_FEED: begin
                    // Start reading from both buffers (staggered)
                    buf_a_rd_start <= 1'b1;
                    buf_b_rd_start <= 1'b1;
                    buf_a_rd_en    <= 1'b1;
                    buf_b_rd_en    <= 1'b1;
                    sa_en          <= 1'b1;
                    compute_count  <= 0;
                    
                    // Clear accumulator only for first K tile
                    if (tile_k == 0)
                        sa_clear_acc <= 1'b1;
                end
                
                S_COMPUTE: begin
                    sa_en          <= 1'b1;
                    buf_a_rd_en    <= 1'b1;
                    buf_b_rd_en    <= 1'b1;
                    compute_count  <= compute_count + 1;
                    compute_cycles <= compute_cycles + 1;
                    
                    // Count MACs: N^2 per cycle (all PEs active)
                    total_macs <= total_macs + (ARRAY_SIZE * ARRAY_SIZE);
                end
                
                S_DRAIN: begin
                    sa_en       <= 1'b0;
                    buf_a_rd_en <= 1'b0;
                    buf_b_rd_en <= 1'b0;
                end
                
                S_STORE: begin
                    obuf_wr_en <= 1'b1;
                end
                
                S_TILE_NEXT: begin
                    load_row_count <= 0;
                    load_col_count <= 0;
                    
                    if (tile_k < num_tiles - 1) begin
                        tile_k <= tile_k + 1;
                    end else begin
                        tile_k <= 0;
                        if (tile_col < num_tiles - 1) begin
                            tile_col <= tile_col + 1;
                        end else begin
                            tile_col <= 0;
                            tile_row <= tile_row + 1;
                        end
                    end
                end
                
                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
