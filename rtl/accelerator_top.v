//============================================================================
// Module: Accelerator Top Level
// Description: Top-level integration of the systolic array accelerator.
//              Connects: Controller FSM ↔ Input Buffers ↔ Systolic Array ↔ Output Buffer
//
//              System Architecture:
//              ┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
//              │ Input     │───→│ Systolic │───→│ Output       │───→│ Host     │
//              │ Buffers   │    │ Array    │    │ Buffer       │    │ Interface│
//              │ (A & B)   │    │ (NxN PE) │    │              │    │          │
//              └──────────┘    └──────────┘    └──────────────┘    └──────────┘
//                    ↑              ↑                ↑                   ↑
//                    └──────────────┴────────────────┴───────────────────┘
//                                    Controller FSM
//
// Parameters:
//   ARRAY_SIZE - Dimension N of the NxN systolic array
//   DATA_WIDTH - Bit width of input operands (INT8)
//   ACC_WIDTH  - Bit width of accumulator
//
// Author: AI Accelerator Project
//============================================================================

module accelerator_top #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter MAX_DIM    = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Host control interface
    input  wire                    start,
    input  wire [$clog2(MAX_DIM):0] mat_dim,
    output wire                    done,
    output wire                    busy,
    
    // Data input interface (for loading matrices)
    input  wire                    data_wr_en,
    input  wire                    data_wr_sel,   // 0=A, 1=B
    input  wire [$clog2(ARRAY_SIZE)-1:0] data_wr_row,
    input  wire [$clog2(ARRAY_SIZE)-1:0] data_wr_col,
    input  wire [DATA_WIDTH-1:0]   data_wr_val,
    
    // Result read interface
    input  wire                    result_rd_en,
    input  wire [$clog2(ARRAY_SIZE)-1:0] result_rd_row,
    input  wire [$clog2(ARRAY_SIZE)-1:0] result_rd_col,
    output wire [ACC_WIDTH-1:0]    result_rd_data,
    output wire                    result_rd_valid,
    output wire                    result_ready,
    
    // Performance counters
    output wire [31:0]             perf_cycle_count,
    output wire [31:0]             perf_compute_cycles,
    output wire [31:0]             perf_total_macs
);

    //------------------------------------------------------------------------
    // Internal wires
    //------------------------------------------------------------------------
    
    // Controller → Buffer A
    wire                            ctrl_buf_a_wr_en;
    wire [$clog2(ARRAY_SIZE)-1:0]   ctrl_buf_a_wr_row;
    wire [$clog2(ARRAY_SIZE)-1:0]   ctrl_buf_a_wr_col;
    wire                            ctrl_buf_a_rd_en;
    wire                            ctrl_buf_a_rd_start;
    
    // Controller → Buffer B
    wire                            ctrl_buf_b_wr_en;
    wire [$clog2(ARRAY_SIZE)-1:0]   ctrl_buf_b_wr_row;
    wire [$clog2(ARRAY_SIZE)-1:0]   ctrl_buf_b_wr_col;
    wire                            ctrl_buf_b_rd_en;
    wire                            ctrl_buf_b_rd_start;
    
    // Controller → Systolic Array
    wire                            ctrl_sa_en;
    wire                            ctrl_sa_clear_acc;
    
    // Controller → Output Buffer
    wire                            ctrl_obuf_wr_en;
    
    // Buffer A → Systolic Array
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] buf_a_data;
    wire                             buf_a_valid;
    
    // Buffer B → Systolic Array
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] buf_b_data;
    wire                             buf_b_valid;
    
    // Systolic Array → Output Buffer
    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] sa_result;
    
    // Mux write enables: host writes when not busy, controller writes when busy
    wire buf_a_wr_en_mux   = busy ? ctrl_buf_a_wr_en : (data_wr_en & ~data_wr_sel);
    wire buf_b_wr_en_mux   = busy ? ctrl_buf_b_wr_en : (data_wr_en &  data_wr_sel);
    wire [$clog2(ARRAY_SIZE)-1:0] buf_a_wr_row_mux = busy ? ctrl_buf_a_wr_row : data_wr_row;
    wire [$clog2(ARRAY_SIZE)-1:0] buf_a_wr_col_mux = busy ? ctrl_buf_a_wr_col : data_wr_col;
    wire [$clog2(ARRAY_SIZE)-1:0] buf_b_wr_row_mux = busy ? ctrl_buf_b_wr_row : data_wr_row;
    wire [$clog2(ARRAY_SIZE)-1:0] buf_b_wr_col_mux = busy ? ctrl_buf_b_wr_col : data_wr_col;

    //------------------------------------------------------------------------
    // Controller FSM
    //------------------------------------------------------------------------
    controller #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .TILE_SIZE  (ARRAY_SIZE),
        .MAX_DIM    (MAX_DIM),
        .SKIP_LOAD  (1)  // Data loaded via host interface before start
    ) u_controller (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .mat_dim         (mat_dim),
        .done            (done),
        .busy            (busy),
        .buf_a_wr_en     (ctrl_buf_a_wr_en),
        .buf_a_wr_row    (ctrl_buf_a_wr_row),
        .buf_a_wr_col    (ctrl_buf_a_wr_col),
        .buf_a_rd_en     (ctrl_buf_a_rd_en),
        .buf_a_rd_start  (ctrl_buf_a_rd_start),
        .buf_b_wr_en     (ctrl_buf_b_wr_en),
        .buf_b_wr_row    (ctrl_buf_b_wr_row),
        .buf_b_wr_col    (ctrl_buf_b_wr_col),
        .buf_b_rd_en     (ctrl_buf_b_rd_en),
        .buf_b_rd_start  (ctrl_buf_b_rd_start),
        .sa_en           (ctrl_sa_en),
        .sa_clear_acc    (ctrl_sa_clear_acc),
        .obuf_wr_en      (ctrl_obuf_wr_en),
        .cycle_count     (perf_cycle_count),
        .compute_cycles  (perf_compute_cycles),
        .total_macs      (perf_total_macs)
    );

    //------------------------------------------------------------------------
    // Input Buffer A (Matrix A - row data)
    //------------------------------------------------------------------------
    input_buffer #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (ARRAY_SIZE)
    ) u_input_buf_a (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (buf_a_wr_en_mux),
        .wr_row    (buf_a_wr_row_mux),
        .wr_col    (buf_a_wr_col_mux),
        .wr_data   (data_wr_val),
        .rd_en     (ctrl_buf_a_rd_en),
        .rd_start  (ctrl_buf_a_rd_start),
        .rd_data   (buf_a_data),
        .rd_valid  (buf_a_valid)
    );

    //------------------------------------------------------------------------
    // Input Buffer B (Matrix B - column data)
    //------------------------------------------------------------------------
    input_buffer #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (ARRAY_SIZE)
    ) u_input_buf_b (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (buf_b_wr_en_mux),
        .wr_row    (buf_b_wr_row_mux),
        .wr_col    (buf_b_wr_col_mux),
        .wr_data   (data_wr_val),
        .rd_en     (ctrl_buf_b_rd_en),
        .rd_start  (ctrl_buf_b_rd_start),
        .rd_data   (buf_b_data),
        .rd_valid  (buf_b_valid)
    );

    //------------------------------------------------------------------------
    // Systolic Array (NxN)
    //------------------------------------------------------------------------
    systolic_array #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_systolic_array (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (ctrl_sa_en),
        .clear_acc (ctrl_sa_clear_acc),
        .a_in      (buf_a_data),
        .b_in      (buf_b_data),
        .result    (sa_result)
    );

    //------------------------------------------------------------------------
    // Output Buffer
    //------------------------------------------------------------------------
    output_buffer #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_output_buf (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (ctrl_obuf_wr_en),
        .wr_data   (sa_result),
        .rd_en     (result_rd_en),
        .rd_row    (result_rd_row),
        .rd_col    (result_rd_col),
        .rd_data   (result_rd_data),
        .rd_valid  (result_rd_valid),
        .buf_ready (result_ready)
    );

endmodule
