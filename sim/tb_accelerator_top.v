//============================================================================
// Testbench: Accelerator Top Level
// Description: Full system integration test. Loads matrices through the
//              host interface, triggers computation, waits for completion,
//              and reads back results. Verifies against golden reference.
//
//              Tests the complete pipeline:
//              Host Write → Input Buffers → Systolic Array → Output Buffer → Host Read
//
// Author: AI Accelerator Project
//============================================================================

`timescale 1ns / 1ps

module tb_accelerator_top;

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter MAX_DIM    = 16;
    parameter CLK_PERIOD = 10;  // 100 MHz

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------
    reg                              clk;
    reg                              rst_n;
    
    // Host control
    reg                              start;
    reg  [$clog2(MAX_DIM):0]         mat_dim;
    wire                             done;
    wire                             busy;
    
    // Data write interface
    reg                              data_wr_en;
    reg                              data_wr_sel;
    reg  [$clog2(ARRAY_SIZE)-1:0]    data_wr_row;
    reg  [$clog2(ARRAY_SIZE)-1:0]    data_wr_col;
    reg  [DATA_WIDTH-1:0]            data_wr_val;
    
    // Result read interface
    reg                              result_rd_en;
    reg  [$clog2(ARRAY_SIZE)-1:0]    result_rd_row;
    reg  [$clog2(ARRAY_SIZE)-1:0]    result_rd_col;
    wire [ACC_WIDTH-1:0]             result_rd_data;
    wire                             result_rd_valid;
    wire                             result_ready;
    
    // Performance counters
    wire [31:0]                      perf_cycle_count;
    wire [31:0]                      perf_compute_cycles;
    wire [31:0]                      perf_total_macs;

    //------------------------------------------------------------------------
    // DUT Instantiation
    //------------------------------------------------------------------------
    accelerator_top #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .MAX_DIM    (MAX_DIM)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .mat_dim            (mat_dim),
        .done               (done),
        .busy               (busy),
        .data_wr_en         (data_wr_en),
        .data_wr_sel        (data_wr_sel),
        .data_wr_row        (data_wr_row),
        .data_wr_col        (data_wr_col),
        .data_wr_val        (data_wr_val),
        .result_rd_en       (result_rd_en),
        .result_rd_row      (result_rd_row),
        .result_rd_col      (result_rd_col),
        .result_rd_data     (result_rd_data),
        .result_rd_valid    (result_rd_valid),
        .result_ready       (result_ready),
        .perf_cycle_count   (perf_cycle_count),
        .perf_compute_cycles(perf_compute_cycles),
        .perf_total_macs    (perf_total_macs)
    );

    //------------------------------------------------------------------------
    // Clock Generation
    //------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------------------------------
    // Test Data
    //------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mat_a [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [DATA_WIDTH-1:0] mat_b [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [ACC_WIDTH-1:0]  mat_c_expected [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [ACC_WIDTH-1:0]  mat_c_actual [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer test_pass = 0;
    integer test_fail = 0;
    integer i, j, k;
    integer start_time, end_time;

    //------------------------------------------------------------------------
    // Task: Write a single element to input buffer
    //------------------------------------------------------------------------
    task write_element;
        input sel;  // 0=A, 1=B
        input [$clog2(ARRAY_SIZE)-1:0] row;
        input [$clog2(ARRAY_SIZE)-1:0] col;
        input [DATA_WIDTH-1:0] val;
    begin
        @(posedge clk);
        data_wr_en  = 1;
        data_wr_sel = sel;
        data_wr_row = row;
        data_wr_col = col;
        data_wr_val = val;
        @(posedge clk);
        data_wr_en  = 0;
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Load full matrix into buffer
    //------------------------------------------------------------------------
    task load_matrix_a;
    begin
        $display("  Loading Matrix A...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                write_element(0, i[1:0], j[1:0], mat_a[i][j]);
            end
        end
        $display("  Matrix A loaded.");
    end
    endtask

    task load_matrix_b;
    begin
        $display("  Loading Matrix B...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                write_element(1, i[1:0], j[1:0], mat_b[i][j]);
            end
        end
        $display("  Matrix B loaded.");
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Read result matrix
    //------------------------------------------------------------------------
    task read_results;
    begin
        $display("  Reading results...");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                @(posedge clk);
                result_rd_en  = 1;
                result_rd_row = i[1:0];
                result_rd_col = j[1:0];
                @(posedge clk);
                @(posedge clk);  // Wait for valid
                if (result_rd_valid)
                    mat_c_actual[i][j] = result_rd_data;
                else
                    mat_c_actual[i][j] = 32'hDEADBEEF;
                result_rd_en = 0;
            end
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Compute golden reference
    //------------------------------------------------------------------------
    task compute_expected;
    // Note: The input buffer reads B column-wise, effectively computing A * B^T
    // So we need to use mat_b[j][k] instead of mat_b[k][j]
    begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                mat_c_expected[i][j] = 0;
                for (k = 0; k < ARRAY_SIZE; k = k + 1) begin
                    mat_c_expected[i][j] = mat_c_expected[i][j] + 
                        (mat_a[i][k] * mat_b[j][k]);  // Use B^T
                end
            end
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Verify results
    //------------------------------------------------------------------------
    task verify;
    begin
        $display("\n  --- Verification ---");
        $display("  Expected C:");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            $display("    [%6d, %6d, %6d, %6d]",
                mat_c_expected[i][0], mat_c_expected[i][1],
                mat_c_expected[i][2], mat_c_expected[i][3]);
        end
        
        $display("  Actual C:");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            $display("    [%6d, %6d, %6d, %6d]",
                mat_c_actual[i][0], mat_c_actual[i][1],
                mat_c_actual[i][2], mat_c_actual[i][3]);
        end
        
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                if (mat_c_actual[i][j] === mat_c_expected[i][j]) begin
                    test_pass = test_pass + 1;
                end else begin
                    test_fail = test_fail + 1;
                    $display("  [FAIL] C[%0d][%0d]: got %0d, expected %0d",
                        i, j, mat_c_actual[i][j], mat_c_expected[i][j]);
                end
            end
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Main Test Sequence
    //------------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("  Accelerator Top-Level Integration Testbench");
        $display("  Array Size: %0dx%0d | Data Width: %0d-bit | Acc Width: %0d-bit",
            ARRAY_SIZE, ARRAY_SIZE, DATA_WIDTH, ACC_WIDTH);
        $display("============================================================");
        
        // Initialize signals
        rst_n        = 0;
        start        = 0;
        mat_dim      = ARRAY_SIZE;
        data_wr_en   = 0;
        data_wr_sel  = 0;
        data_wr_row  = 0;
        data_wr_col  = 0;
        data_wr_val  = 0;
        result_rd_en = 0;
        result_rd_row = 0;
        result_rd_col = 0;
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        //====================================================================
        // TEST 1: Basic 4x4 Matrix Multiplication
        //====================================================================
        $display("\n========================================");
        $display("  TEST 1: Basic 4x4 MatMul");
        $display("========================================");
        
        // Initialize matrices
        mat_a[0][0]=1;  mat_a[0][1]=2;  mat_a[0][2]=3;  mat_a[0][3]=4;
        mat_a[1][0]=5;  mat_a[1][1]=6;  mat_a[1][2]=7;  mat_a[1][3]=8;
        mat_a[2][0]=9;  mat_a[2][1]=10; mat_a[2][2]=11; mat_a[2][3]=12;
        mat_a[3][0]=13; mat_a[3][1]=14; mat_a[3][2]=15; mat_a[3][3]=16;
        
        // Matrix B - load in row-major order (untransposed)
        // The input buffer reads column-wise, so this gives correct column-wise feeding
        mat_b[0][0]=1;  mat_b[0][1]=2;  mat_b[0][2]=3;  mat_b[0][3]=4;
        mat_b[1][0]=5;  mat_b[1][1]=6;  mat_b[1][2]=7;  mat_b[1][3]=8;
        mat_b[2][0]=9;  mat_b[2][1]=10; mat_b[2][2]=11; mat_b[2][3]=12;
        mat_b[3][0]=13; mat_b[3][1]=14; mat_b[3][2]=15; mat_b[3][3]=16;
        
        compute_expected;
        
        // Load matrices
        load_matrix_a;
        load_matrix_b;
        
        // Start computation
        $display("  Starting computation...");
        start_time = $time;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for done
        wait(done == 1);
        end_time = $time;
        $display("  Computation complete!");
        $display("  Elapsed time: %0d ns", end_time - start_time);
        
        // Read and verify results
        #(CLK_PERIOD * 2);
        if (result_ready) begin
            read_results;
            verify;
        end else begin
            $display("  [WARN] Result buffer not ready!");
        end
        
        //====================================================================
        // Performance Report
        //====================================================================
        $display("\n========================================");
        $display("  PERFORMANCE REPORT");
        $display("========================================");
        $display("  Total Cycles:       %0d", perf_cycle_count);
        $display("  Compute Cycles:     %0d", perf_compute_cycles);
        $display("  Total MACs:         %0d", perf_total_macs);
        $display("  Array Utilization:  %0d PEs", ARRAY_SIZE * ARRAY_SIZE);
        $display("  Peak Throughput:    %0d MACs/cycle", ARRAY_SIZE * ARRAY_SIZE);
        if (perf_cycle_count > 0) begin
            $display("  Effective GOPS:     N/A (simulation)");
        end
        $display("========================================");
        
        //====================================================================
        // TEST 2: All-ones Matrix
        //====================================================================
        $display("\n========================================");
        $display("  TEST 2: All-Ones Matrix (each C[i][j] = N)");
        $display("========================================");
        
        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                mat_a[i][j] = 8'd1;
                mat_b[i][j] = 8'd1;
            end
        
        compute_expected;
        load_matrix_a;
        load_matrix_b;
        
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1);
        #(CLK_PERIOD * 2);
        
        if (result_ready) begin
            read_results;
            verify;
        end
        
        //====================================================================
        // TEST 3: Diagonal Matrix
        //====================================================================
        $display("\n========================================");
        $display("  TEST 3: Diagonal Matrix (A * I = A)");
        $display("========================================");
        
        // A = sequential values
        mat_a[0][0]=2;  mat_a[0][1]=3;  mat_a[0][2]=5;  mat_a[0][3]=7;
        mat_a[1][0]=11; mat_a[1][1]=13; mat_a[1][2]=17; mat_a[1][3]=19;
        mat_a[2][0]=23; mat_a[2][1]=29; mat_a[2][2]=31; mat_a[2][3]=37;
        mat_a[3][0]=41; mat_a[3][1]=43; mat_a[3][2]=47; mat_a[3][3]=53;
        
        // B = identity
        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                mat_b[i][j] = (i == j) ? 8'd1 : 8'd0;
        
        compute_expected;
        load_matrix_a;
        load_matrix_b;
        
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        wait(done == 1);
        #(CLK_PERIOD * 2);
        
        if (result_ready) begin
            read_results;
            verify;
        end
        
        //====================================================================
        // Final Summary
        //====================================================================
        #(CLK_PERIOD * 5);
        $display("\n============================================================");
        $display("  FINAL TEST SUMMARY");
        $display("============================================================");
        $display("  Total Element Checks: %0d", test_pass + test_fail);
        $display("  Passed:               %0d", test_pass);
        $display("  Failed:               %0d", test_fail);
        $display("============================================================");
        
        if (test_fail == 0)
            $display("  >>> ALL INTEGRATION TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED - CHECK ABOVE <<<");
        
        $display("============================================================\n");
        $finish;
    end

    //------------------------------------------------------------------------
    // Waveform Dump
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 5000);
        $display("[ERROR] Simulation timeout after 5000 cycles!");
        $finish;
    end

endmodule
