//============================================================================
// Testbench: Processing Element (PE)
// Description: Verifies MAC operation, data forwarding, reset, and
//              accumulator clear functionality of a single PE.
//
// Author: AI Accelerator Project
//============================================================================

`timescale 1ns / 1ps

module tb_pe;

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;
    parameter CLK_PERIOD = 10;  // 100 MHz

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------
    reg                    clk;
    reg                    rst_n;
    reg                    en;
    reg                    clear_acc;
    reg  [DATA_WIDTH-1:0]  a_in;
    reg  [DATA_WIDTH-1:0]  b_in;
    wire [DATA_WIDTH-1:0]  a_out;
    wire [DATA_WIDTH-1:0]  b_out;
    wire [ACC_WIDTH-1:0]   acc;

    //------------------------------------------------------------------------
    // DUT Instantiation
    //------------------------------------------------------------------------
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .clear_acc (clear_acc),
        .a_in      (a_in),
        .b_in      (b_in),
        .a_out     (a_out),
        .b_out     (b_out),
        .acc       (acc)
    );

    //------------------------------------------------------------------------
    // Clock Generation
    //------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------------------------------
    // Test Variables
    //------------------------------------------------------------------------
    integer test_pass = 0;
    integer test_fail = 0;
    integer total_tests = 0;
    reg [ACC_WIDTH-1:0] expected_acc;

    //------------------------------------------------------------------------
    // Task: Check Result
    //------------------------------------------------------------------------
    task check_result;
        input [ACC_WIDTH-1:0] expected;
        input [255:0] test_name;  // Use fixed-width for Verilog compatibility
    begin
        total_tests = total_tests + 1;
        if (acc === expected) begin
            $display("[PASS] %0s: acc = %0d (expected %0d)", test_name, acc, expected);
            test_pass = test_pass + 1;
        end else begin
            $display("[FAIL] %0s: acc = %0d (expected %0d)", test_name, acc, expected);
            test_fail = test_fail + 1;
        end
    end
    endtask

    //------------------------------------------------------------------------
    // Test Stimulus
    //------------------------------------------------------------------------
    initial begin
        $display("============================================");
        $display("  PE Testbench - Starting Tests");
        $display("============================================");
        
        // Initialize
        rst_n     = 0;
        en        = 0;
        clear_acc = 0;
        a_in      = 0;
        b_in      = 0;
        
        // Reset
        #(CLK_PERIOD * 3);
        rst_n = 1;
        #(CLK_PERIOD);
        
        //--------------------------------------------------------------------
        // Test 1: Basic MAC operation (3 × 4 = 12)
        //--------------------------------------------------------------------
        $display("\n--- Test 1: Basic MAC (3 x 4) ---");
        en   = 1;
        a_in = 8'd3;
        b_in = 8'd4;
        @(posedge clk); #1;
        check_result(32'd12, "Basic MAC 3x4");
        
        //--------------------------------------------------------------------
        // Test 2: Accumulation (12 + 5 × 6 = 42)
        //--------------------------------------------------------------------
        $display("\n--- Test 2: Accumulation (+ 5 x 6) ---");
        a_in = 8'd5;
        b_in = 8'd6;
        @(posedge clk); #1;
        check_result(32'd42, "Accumulate 5x6");
        
        //--------------------------------------------------------------------
        // Test 3: Data forwarding check
        //--------------------------------------------------------------------
        $display("\n--- Test 3: Data Forwarding ---");
        a_in = 8'd7;
        b_in = 8'd8;
        @(posedge clk); #1;
        total_tests = total_tests + 1;
        if (a_out === 8'd7 && b_out === 8'd8) begin
            $display("[PASS] Data forwarding: a_out=%0d, b_out=%0d", a_out, b_out);
            test_pass = test_pass + 1;
        end else begin
            $display("[FAIL] Data forwarding: a_out=%0d (exp 7), b_out=%0d (exp 8)", a_out, b_out);
            test_fail = test_fail + 1;
        end
        
        //--------------------------------------------------------------------
        // Test 4: Enable gating (acc should not change when en=0)
        //--------------------------------------------------------------------
        $display("\n--- Test 4: Enable Gating ---");
        expected_acc = acc;  // Save current value
        en   = 0;
        a_in = 8'd100;
        b_in = 8'd100;
        @(posedge clk); #1;
        check_result(expected_acc, "Enable gating");
        
        //--------------------------------------------------------------------
        // Test 5: Clear accumulator
        //--------------------------------------------------------------------
        $display("\n--- Test 5: Clear Accumulator ---");
        en        = 0;
        clear_acc = 1;
        @(posedge clk); #1;
        check_result(32'd0, "Clear accumulator");
        clear_acc = 0;
        
        //--------------------------------------------------------------------
        // Test 6: Multiple MACs (dot product simulation)
        // Compute: 1*1 + 2*2 + 3*3 + 4*4 = 1 + 4 + 9 + 16 = 30
        //--------------------------------------------------------------------
        $display("\n--- Test 6: Dot Product (1*1 + 2*2 + 3*3 + 4*4 = 30) ---");
        en = 1;
        
        a_in = 8'd1; b_in = 8'd1;
        @(posedge clk); #1;
        
        a_in = 8'd2; b_in = 8'd2;
        @(posedge clk); #1;
        
        a_in = 8'd3; b_in = 8'd3;
        @(posedge clk); #1;
        
        a_in = 8'd4; b_in = 8'd4;
        @(posedge clk); #1;
        
        check_result(32'd30, "Dot product");
        
        //--------------------------------------------------------------------
        // Test 7: Max value test (255 × 255 = 65025)
        //--------------------------------------------------------------------
        $display("\n--- Test 7: Max Value (255 x 255) ---");
        clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;
        
        en   = 1;
        a_in = 8'd255;
        b_in = 8'd255;
        @(posedge clk); #1;
        check_result(32'd65025, "Max value 255x255");
        
        //--------------------------------------------------------------------
        // Test 8: Reset during operation
        //--------------------------------------------------------------------
        $display("\n--- Test 8: Reset During Operation ---");
        a_in = 8'd10;
        b_in = 8'd10;
        @(posedge clk); #1;
        
        // Apply reset and check accumulator is cleared
        rst_n = 0;
        @(posedge clk); #1;
        total_tests = total_tests + 1;
        if (acc === 32'd0) begin
            $display("[PASS] Reset clears acc: acc = %0d (expected 0)", acc);
            test_pass = test_pass + 1;
        end else begin
            $display("[FAIL] Reset clears acc: acc = %0d (expected 0)", acc);
            test_fail = test_fail + 1;
        end
        
        // Release reset and verify normal operation resumes
        rst_n = 1;
        @(posedge clk); #1;
        check_result(32'd100, "Operation resumes after reset");
        
        //--------------------------------------------------------------------
        // Summary
        //--------------------------------------------------------------------
        #(CLK_PERIOD * 2);
        $display("\n============================================");
        $display("  PE Testbench - Results Summary");
        $display("============================================");
        $display("  Total Tests: %0d", total_tests);
        $display("  Passed:      %0d", test_pass);
        $display("  Failed:      %0d", test_fail);
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
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);
    end

endmodule
