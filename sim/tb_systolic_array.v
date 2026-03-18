//============================================================================
// Testbench: Systolic Array (4x4)
// Description: Verifies 4x4 matrix multiplication C = A x B using the
//              systolic array with proper staggered (skewed) data feeding.
//
//              Test matrices:
//              A = [[1, 2, 3, 4],    B = [[1, 5, 9,  13],
//                   [5, 6, 7, 8],         [2, 6, 10, 14],
//                   [9, 10,11,12],        [3, 7, 11, 15],
//                   [13,14,15,16]]        [4, 8, 12, 16]]
//
//              Expected C = A x B:
//              C = [[30,  70,  110, 150],
//                   [70,  174, 278, 382],
//                   [110, 278, 446, 614],
//                   [150, 382, 614, 846]]
//
// Author: AI Accelerator Project
//============================================================================

`timescale 1ns / 1ps

module tb_systolic_array;

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter CLK_PERIOD = 10;

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------
    reg                                     clk;
    reg                                     rst_n;
    reg                                     en;
    reg                                     clear_acc;
    reg  [ARRAY_SIZE*DATA_WIDTH-1:0]        a_in;
    reg  [ARRAY_SIZE*DATA_WIDTH-1:0]        b_in;
    wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] result;

    //------------------------------------------------------------------------
    // DUT Instantiation
    //------------------------------------------------------------------------
    systolic_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .clear_acc (clear_acc),
        .a_in      (a_in),
        .b_in      (b_in),
        .result    (result)
    );

    //------------------------------------------------------------------------
    // Clock Generation
    //------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------------------------------
    // Test Data: Matrices A and B
    //------------------------------------------------------------------------
    // A[row][col] - stored row-major
    reg [DATA_WIDTH-1:0] mat_a [0:3][0:3];
    // B[row][col] - stored row-major
    reg [DATA_WIDTH-1:0] mat_b [0:3][0:3];
    // Expected C[row][col]
    reg [ACC_WIDTH-1:0]  mat_c_expected [0:3][0:3];

    //------------------------------------------------------------------------
    // Test Variables
    //------------------------------------------------------------------------
    integer test_pass = 0;
    integer test_fail = 0;
    integer i, j, k;
    integer cycle;
    reg [ACC_WIDTH-1:0] pe_result;

    //------------------------------------------------------------------------
    // Initialize Test Matrices
    //------------------------------------------------------------------------
    task init_matrices;
    begin
        // Matrix A
        mat_a[0][0] = 8'd1;  mat_a[0][1] = 8'd2;  mat_a[0][2] = 8'd3;  mat_a[0][3] = 8'd4;
        mat_a[1][0] = 8'd5;  mat_a[1][1] = 8'd6;  mat_a[1][2] = 8'd7;  mat_a[1][3] = 8'd8;
        mat_a[2][0] = 8'd9;  mat_a[2][1] = 8'd10; mat_a[2][2] = 8'd11; mat_a[2][3] = 8'd12;
        mat_a[3][0] = 8'd13; mat_a[3][1] = 8'd14; mat_a[3][2] = 8'd15; mat_a[3][3] = 8'd16;
        
        // Matrix B
        mat_b[0][0] = 8'd1;  mat_b[0][1] = 8'd5;  mat_b[0][2] = 8'd9;  mat_b[0][3] = 8'd13;
        mat_b[1][0] = 8'd2;  mat_b[1][1] = 8'd6;  mat_b[1][2] = 8'd10; mat_b[1][3] = 8'd14;
        mat_b[2][0] = 8'd3;  mat_b[2][1] = 8'd7;  mat_b[2][2] = 8'd11; mat_b[2][3] = 8'd15;
        mat_b[3][0] = 8'd4;  mat_b[3][1] = 8'd8;  mat_b[3][2] = 8'd12; mat_b[3][3] = 8'd16;
        
        // Compute expected C = A x B
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                mat_c_expected[i][j] = 0;
                for (k = 0; k < 4; k = k + 1) begin
                    mat_c_expected[i][j] = mat_c_expected[i][j] + 
                        (mat_a[i][k] * mat_b[k][j]);
                end
            end
        end
        
        // Display expected results
        $display("\nExpected C = A x B:");
        for (i = 0; i < 4; i = i + 1) begin
            $display("  [%4d, %4d, %4d, %4d]", 
                mat_c_expected[i][0], mat_c_expected[i][1],
                mat_c_expected[i][2], mat_c_expected[i][3]);
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Feed staggered data to systolic array
    // Systolic feeding pattern:
    //   Cycle 0: Row0 gets A[0][0], Col0 gets B[0][0]
    //   Cycle 1: Row0 gets A[0][1], Row1 gets A[1][0], Col0 gets B[1][0], Col1 gets B[0][1]
    //   Cycle 2: Row0 gets A[0][2], Row1 gets A[1][1], Row2 gets A[2][0], ...
    //   etc.
    //------------------------------------------------------------------------
    task feed_systolic;
        integer c, r;
        reg [DATA_WIDTH-1:0] a_val, b_val;
    begin
        // Total feeding cycles: N + K - 1 = 4 + 4 - 1 = 7
        for (c = 0; c < 7; c = c + 1) begin
            // Build a_in: each row gets its staggered element
            for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
                if (c >= r && (c - r) < ARRAY_SIZE) begin
                    a_val = mat_a[r][c - r];
                end else begin
                    a_val = 8'd0;
                end
                a_in[r*DATA_WIDTH +: DATA_WIDTH] = a_val;
            end
            
            // Build b_in: each column gets its staggered element
            for (r = 0; r < ARRAY_SIZE; r = r + 1) begin
                if (c >= r && (c - r) < ARRAY_SIZE) begin
                    b_val = mat_b[c - r][r];
                end else begin
                    b_val = 8'd0;
                end
                b_in[r*DATA_WIDTH +: DATA_WIDTH] = b_val;
            end
            
            $display("  Cycle %0d: a_in=[%3d,%3d,%3d,%3d] b_in=[%3d,%3d,%3d,%3d]",
                c,
                a_in[0*DATA_WIDTH +: DATA_WIDTH],
                a_in[1*DATA_WIDTH +: DATA_WIDTH],
                a_in[2*DATA_WIDTH +: DATA_WIDTH],
                a_in[3*DATA_WIDTH +: DATA_WIDTH],
                b_in[0*DATA_WIDTH +: DATA_WIDTH],
                b_in[1*DATA_WIDTH +: DATA_WIDTH],
                b_in[2*DATA_WIDTH +: DATA_WIDTH],
                b_in[3*DATA_WIDTH +: DATA_WIDTH]);
            
            @(posedge clk);
        end
        
        // Feed zeros for remaining pipeline drain
        a_in = 0;
        b_in = 0;
        repeat(ARRAY_SIZE) @(posedge clk);
    end
    endtask

    //------------------------------------------------------------------------
    // Task: Verify Results
    //------------------------------------------------------------------------
    task verify_results;
    begin
        $display("\n--- Verifying Results ---");
        $display("Actual C (from systolic array):");
        
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                pe_result = result[(i*ARRAY_SIZE + j)*ACC_WIDTH +: ACC_WIDTH];
                
                if (pe_result === mat_c_expected[i][j]) begin
                    test_pass = test_pass + 1;
                end else begin
                    test_fail = test_fail + 1;
                    $display("  [FAIL] C[%0d][%0d] = %0d (expected %0d)", 
                        i, j, pe_result, mat_c_expected[i][j]);
                end
            end
            
            $display("  [%4d, %4d, %4d, %4d]",
                result[(i*ARRAY_SIZE + 0)*ACC_WIDTH +: ACC_WIDTH],
                result[(i*ARRAY_SIZE + 1)*ACC_WIDTH +: ACC_WIDTH],
                result[(i*ARRAY_SIZE + 2)*ACC_WIDTH +: ACC_WIDTH],
                result[(i*ARRAY_SIZE + 3)*ACC_WIDTH +: ACC_WIDTH]);
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Main Test Sequence
    //------------------------------------------------------------------------
    initial begin
        $display("============================================");
        $display("  Systolic Array 4x4 Testbench");
        $display("============================================");
        
        // Initialize
        rst_n     = 0;
        en        = 0;
        clear_acc = 0;
        a_in      = 0;
        b_in      = 0;
        
        // Initialize test matrices
        init_matrices;
        
        // Reset
        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD);
        
        // Clear accumulators
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        
        //--------------------------------------------------------------------
        // Test 1: Full 4x4 Matrix Multiplication
        //--------------------------------------------------------------------
        $display("\n--- Test 1: 4x4 Matrix Multiplication ---");
        $display("Feeding staggered data...");
        en = 1;
        feed_systolic;
        en = 0;
        
        // Wait for pipeline to settle
        #(CLK_PERIOD * 2);
        
        // Verify
        verify_results;
        
        //--------------------------------------------------------------------
        // Test 2: Identity Matrix Test
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Identity Matrix Test ---");
        $display("A x I should equal A");
        
        // Full reset between tests - hold clear_acc for more cycles
        clear_acc = 1;
        en = 1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        clear_acc = 0;
        en = 0;
        @(posedge clk);
        
        // Set B to identity
        mat_b[0][0] = 8'd1; mat_b[0][1] = 8'd0; mat_b[0][2] = 8'd0; mat_b[0][3] = 8'd0;
        mat_b[1][0] = 8'd0; mat_b[1][1] = 8'd1; mat_b[1][2] = 8'd0; mat_b[1][3] = 8'd0;
        mat_b[2][0] = 8'd0; mat_b[2][1] = 8'd0; mat_b[2][2] = 8'd1; mat_b[2][3] = 8'd0;
        mat_b[3][0] = 8'd0; mat_b[3][1] = 8'd0; mat_b[3][2] = 8'd0; mat_b[3][3] = 8'd1;
        
        // Recompute expected
        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 4; j = j + 1) begin
                mat_c_expected[i][j] = 0;
                for (k = 0; k < 4; k = k + 1)
                    mat_c_expected[i][j] = mat_c_expected[i][j] + mat_a[i][k] * mat_b[k][j];
            end
        
        en = 1;
        feed_systolic;
        en = 0;
        #(CLK_PERIOD * 2);
        
        verify_results;
        
        //--------------------------------------------------------------------
        // Summary
        //--------------------------------------------------------------------
        #(CLK_PERIOD * 5);
        $display("\n============================================");
        $display("  Systolic Array Testbench - Results");
        $display("============================================");
        $display("  Total Checks: %0d", test_pass + test_fail);
        $display("  Passed:       %0d", test_pass);
        $display("  Failed:       %0d", test_fail);
        $display("============================================");
        
        if (test_fail == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        
        $display("============================================\n");
        $finish;
    end

    //------------------------------------------------------------------------
    // Waveform Dump
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

    //------------------------------------------------------------------------
    // Timeout watchdog
    //------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 500);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
