//============================================================================
// Showcase Testbench: 4x4 Systolic Array Matrix Multiplication
// Description: Simple demonstration of the AI Accelerator
//              Shows a single 4x4 matrix multiplication
//============================================================================

`timescale 1ns / 1ps

module tb_showcase;

    // Parameters
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;
    parameter CLK_PERIOD = 10;

    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Host control
    reg start;
    reg [4:0] mat_dim;
    wire done;
    wire busy;
    
    // Data write interface
    reg data_wr_en;
    reg data_wr_sel;  // 0=A, 1=B
    reg [1:0] data_wr_row;
    reg [1:0] data_wr_col;
    reg [DATA_WIDTH-1:0] data_wr_val;
    
    // Result read interface
    reg result_rd_en;
    reg [1:0] result_rd_row;
    reg [1:0] result_rd_col;
    wire [ACC_WIDTH-1:0] result_rd_data;
    wire result_rd_valid;
    wire result_ready;

    // DUT
    accelerator_top #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mat_dim(2'd3),  // 4x4-1
        .done(done),
        .busy(busy),
        .data_wr_en(data_wr_en),
        .data_wr_sel(data_wr_sel),
        .data_wr_row(data_wr_row),
        .data_wr_col(data_wr_col),
        .data_wr_val(data_wr_val),
        .result_rd_en(result_rd_en),
        .result_rd_row(result_rd_row),
        .result_rd_col(result_rd_col),
        .result_rd_data(result_rd_data),
        .result_rd_valid(result_rd_valid),
        .result_ready(result_ready)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Test matrices (4x4)
    reg [DATA_WIDTH-1:0] A [0:3][0:3];
    reg [DATA_WIDTH-1:0] B [0:3][0:3];
    
    integer i, j;

    initial begin
        $display("========================================");
        $display("  4x4 Matrix Multiplication Showcase");
        $display("========================================");
        
        // Initialize matrices
        // A = [[1,2,3,4], [5,6,7,8], [9,10,11,12], [13,14,15,16]]
        A[0][0]=1;  A[0][1]=2;  A[0][2]=3;  A[0][3]=4;
        A[1][0]=5;  A[1][1]=6;  A[1][2]=7;  A[1][3]=8;
        A[2][0]=9;  A[2][1]=10; A[2][2]=11; A[2][3]=12;
        A[3][0]=13; A[3][1]=14; A[3][2]=15; A[3][3]=16;
        
        // B = [[1,2,3,4], [5,6,7,8], [9,10,11,12], [13,14,15,16]]
        B[0][0]=1;  B[0][1]=2;  B[0][2]=3;  B[0][3]=4;
        B[1][0]=5;  B[1][1]=6;  B[1][2]=7;  B[1][3]=8;
        B[2][0]=9;  B[2][1]=10; B[2][2]=11; B[2][3]=12;
        B[3][0]=13; B[3][1]=14; B[3][2]=15; B[3][3]=16;

        // Print input matrices
        $display("\nMatrix A:");
        for (i=0; i<4; i=i+1) begin
            $display("  [%d, %d, %d, %d]", A[i][0], A[i][1], A[i][2], A[i][3]);
        end
        
        $display("\nMatrix B:");
        for (i=0; i<4; i=i+1) begin
            $display("  [%d, %d, %d, %d]", B[i][0], B[i][1], B[i][2], B[i][3]);
        end
        
        // Reset
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;

        // Load Matrix A
        $display("\nLoading Matrix A...");
        for (i=0; i<4; i=i+1) begin
            for (j=0; j<4; j=j+1) begin
                @(posedge clk);
                data_wr_en = 1;
                data_wr_sel = 0;  // A
                data_wr_row = i;
                data_wr_col = j;
                data_wr_val = A[i][j];
            end
        end
        @(posedge clk);
        data_wr_en = 0;

        // Load Matrix B
        $display("Loading Matrix B...");
        for (i=0; i<4; i=i+1) begin
            for (j=0; j<4; j=j+1) begin
                @(posedge clk);
                data_wr_en = 1;
                data_wr_sel = 1;  // B
                data_wr_row = i;
                data_wr_col = j;
                data_wr_val = B[i][j];
            end
        end
        @(posedge clk);
        data_wr_en = 0;

        // Start computation
        $display("Starting computation...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done
        wait(done == 1);
        $display("Computation complete!");

        // Read results
        #20;
        $display("\nResult Matrix C = A x B:");
        for (i=0; i<4; i=i+1) begin
            for (j=0; j<4; j=j+1) begin
                @(posedge clk);
                result_rd_en = 1;
                result_rd_row = i;
                result_rd_col = j;
                #1;
                $write("  %d", result_rd_data);
            end
            $display("");
        end
        
        $display("========================================");
        $display("  Showcase Complete!");
        $display("========================================");
        
        #10;
        $finish;
    end

endmodule
