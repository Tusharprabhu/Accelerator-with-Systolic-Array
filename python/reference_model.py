#!/usr/bin/env python3
"""
Reference Model: Systolic Array Matrix Multiplication
=====================================================
Python golden reference for verifying RTL simulation results.
Implements both naive and systolic-style matrix multiplication
to generate expected outputs for testbench verification.

Features:
- Naive matrix multiplication (golden reference)
- Cycle-accurate systolic array simulation
- Staggered data feeding pattern generation
- Result comparison and reporting
- Test vector generation for Verilog testbenches

Author: AI Accelerator Project
"""

import numpy as np
import json
import os
from typing import Tuple, List


class SystolicArrayModel:
    """Cycle-accurate Python model of the systolic array."""
    
    def __init__(self, array_size: int = 4, data_width: int = 8, acc_width: int = 32):
        self.N = array_size
        self.data_width = data_width
        self.acc_width = acc_width
        self.max_val = (1 << data_width) - 1  # 255 for 8-bit
        
        # PE grid: accumulators
        self.acc = np.zeros((self.N, self.N), dtype=np.int64)
        
        # PE grid: registered a and b values
        self.a_reg = np.zeros((self.N, self.N), dtype=np.int64)
        self.b_reg = np.zeros((self.N, self.N), dtype=np.int64)
        
        # Cycle counter
        self.cycle = 0
        
    def reset(self):
        """Reset all PE accumulators and registers."""
        self.acc = np.zeros((self.N, self.N), dtype=np.int64)
        self.a_reg = np.zeros((self.N, self.N), dtype=np.int64)
        self.b_reg = np.zeros((self.N, self.N), dtype=np.int64)
        self.cycle = 0
    
    def generate_skewed_inputs(self, A: np.ndarray, B: np.ndarray) -> Tuple[List, List]:
        """
        Generate staggered (skewed) input sequences for systolic feeding.
        
        For an NxK @ KxN multiplication:
        - Row i of A is delayed by i cycles
        - Column j of B is delayed by j cycles
        
        Returns:
            a_inputs: List of arrays, one per cycle. Each array has N elements (one per row)
            b_inputs: List of arrays, one per cycle. Each array has N elements (one per col)
        """
        N = self.N
        K = A.shape[1]
        total_cycles = N + K - 1
        
        a_inputs = []
        b_inputs = []
        
        for c in range(total_cycles):
            a_cycle = np.zeros(N, dtype=np.int64)
            b_cycle = np.zeros(N, dtype=np.int64)
            
            for row in range(N):
                # Row 'row' gets element A[row][c - row] at cycle c
                idx = c - row
                if 0 <= idx < K:
                    a_cycle[row] = A[row][idx]
            
            for col in range(N):
                # Column 'col' gets element B[c - col][col] at cycle c
                idx = c - col
                if 0 <= idx < K:
                    b_cycle[col] = B[idx][col]
            
            a_inputs.append(a_cycle)
            b_inputs.append(b_cycle)
        
        return a_inputs, b_inputs
    
    def step(self, a_in: np.ndarray, b_in: np.ndarray):
        """
        Execute one clock cycle of the systolic array.
        
        Data flow:
        - a propagates left → right
        - b propagates top → bottom
        - Each PE: acc += a * b
        """
        N = self.N
        
        # New registers for this cycle
        new_a = np.zeros((N, N), dtype=np.int64)
        new_b = np.zeros((N, N), dtype=np.int64)
        
        for i in range(N):
            for j in range(N):
                # Get input: from left neighbor or external input
                if j == 0:
                    a_val = a_in[i]
                else:
                    a_val = self.a_reg[i][j-1]
                
                # Get input: from top neighbor or external input
                if i == 0:
                    b_val = b_in[j]
                else:
                    b_val = self.b_reg[i-1][j]
                
                # MAC operation
                self.acc[i][j] += a_val * b_val
                
                # Forward data
                new_a[i][j] = a_val
                new_b[i][j] = b_val
        
        self.a_reg = new_a
        self.b_reg = new_b
        self.cycle += 1
    
    def compute(self, A: np.ndarray, B: np.ndarray) -> np.ndarray:
        """
        Full systolic array computation: C = A × B
        
        Args:
            A: Input matrix (NxK)
            B: Input matrix (KxN)
            
        Returns:
            C: Result matrix (NxN)
        """
        self.reset()
        
        # Generate staggered inputs
        a_inputs, b_inputs = self.generate_skewed_inputs(A, B)
        
        # Feed through systolic array
        for a_in, b_in in zip(a_inputs, b_inputs):
            self.step(a_in, b_in)
        
        # Drain remaining pipeline (feed zeros)
        for _ in range(self.N):
            self.step(np.zeros(self.N, dtype=np.int64), 
                     np.zeros(self.N, dtype=np.int64))
        
        return self.acc.copy()


def naive_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """Standard matrix multiplication (golden reference)."""
    return A @ B


def generate_test_vectors(test_name: str, A: np.ndarray, B: np.ndarray, 
                          output_dir: str = "../sim/vectors"):
    """Generate test vectors in a format readable by Verilog $readmemh."""
    os.makedirs(output_dir, exist_ok=True)
    
    N = A.shape[0]
    
    # Write matrix A (hex format)
    with open(os.path.join(output_dir, f"{test_name}_a.hex"), 'w') as f:
        for i in range(N):
            for j in range(N):
                f.write(f"{int(A[i][j]):02x}\n")
    
    # Write matrix B (hex format)
    with open(os.path.join(output_dir, f"{test_name}_b.hex"), 'w') as f:
        for i in range(N):
            for j in range(N):
                f.write(f"{int(B[i][j]):02x}\n")
    
    # Write expected C (hex format, 32-bit)
    C = naive_matmul(A, B)
    with open(os.path.join(output_dir, f"{test_name}_c_expected.hex"), 'w') as f:
        for i in range(N):
            for j in range(N):
                f.write(f"{int(C[i][j]):08x}\n")
    
    print(f"  Test vectors written to {output_dir}/{test_name}_*.hex")
    return C


def run_verification():
    """Run full verification suite."""
    print("=" * 60)
    print("  Systolic Array Reference Model - Verification Suite")
    print("=" * 60)
    
    N = 4
    model = SystolicArrayModel(array_size=N)
    all_pass = True
    
    # ===== Test 1: Basic 4x4 =====
    print("\n--- Test 1: Basic 4x4 Matrix Multiplication ---")
    A = np.array([
        [1,  2,  3,  4],
        [5,  6,  7,  8],
        [9,  10, 11, 12],
        [13, 14, 15, 16]
    ], dtype=np.int64)
    
    B = np.array([
        [1,  5,  9,  13],
        [2,  6,  10, 14],
        [3,  7,  11, 15],
        [4,  8,  12, 16]
    ], dtype=np.int64)
    
    C_golden = naive_matmul(A, B)
    C_systolic = model.compute(A, B)
    
    print(f"  A =\n{A}")
    print(f"  B =\n{B}")
    print(f"  C (golden)   =\n{C_golden}")
    print(f"  C (systolic) =\n{C_systolic}")
    
    if np.array_equal(C_golden, C_systolic):
        print("  [PASS] Systolic matches golden reference")
    else:
        print("  [FAIL] Mismatch detected!")
        all_pass = False
    
    # Generate test vectors
    generate_test_vectors("test1_basic", A, B)
    
    # ===== Test 2: Identity Matrix =====
    print("\n--- Test 2: Identity Matrix (A * I = A) ---")
    I = np.eye(N, dtype=np.int64)
    C_systolic = model.compute(A, I)
    
    if np.array_equal(A, C_systolic):
        print("  [PASS] A x I = A")
    else:
        print("  [FAIL] A x I != A")
        all_pass = False
    
    generate_test_vectors("test2_identity", A, I)
    
    # ===== Test 3: All Ones =====
    print("\n--- Test 3: All-Ones Matrix ---")
    ones = np.ones((N, N), dtype=np.int64)
    C_golden = naive_matmul(ones, ones)
    C_systolic = model.compute(ones, ones)
    
    print(f"  Expected: all {N}s")
    print(f"  C (systolic) =\n{C_systolic}")
    
    if np.array_equal(C_golden, C_systolic):
        print("  [PASS]")
    else:
        print("  [FAIL]")
        all_pass = False
    
    generate_test_vectors("test3_ones", ones, ones)
    
    # ===== Test 4: Random Matrix =====
    print("\n--- Test 4: Random Matrix (INT8 range) ---")
    np.random.seed(42)
    A_rand = np.random.randint(0, 256, (N, N), dtype=np.int64)
    B_rand = np.random.randint(0, 256, (N, N), dtype=np.int64)
    
    C_golden = naive_matmul(A_rand, B_rand)
    C_systolic = model.compute(A_rand, B_rand)
    
    print(f"  A =\n{A_rand}")
    print(f"  B =\n{B_rand}")
    print(f"  C (golden)   =\n{C_golden}")
    print(f"  C (systolic) =\n{C_systolic}")
    
    if np.array_equal(C_golden, C_systolic):
        print("  [PASS]")
    else:
        print("  [FAIL]")
        all_pass = False
    
    generate_test_vectors("test4_random", A_rand, B_rand)
    
    # ===== Test 5: Max Values (Overflow Check) =====
    print("\n--- Test 5: Max Values (255 x 255) ---")
    A_max = np.full((N, N), 255, dtype=np.int64)
    B_max = np.full((N, N), 255, dtype=np.int64)
    
    C_golden = naive_matmul(A_max, B_max)
    C_systolic = model.compute(A_max, B_max)
    
    print(f"  Each C[i][j] should be: {255 * 255 * N} = {N} x 65025")
    print(f"  C (systolic) =\n{C_systolic}")
    
    if np.array_equal(C_golden, C_systolic):
        print("  [PASS] (no overflow in 32-bit accumulator)")
    else:
        print("  [FAIL]")
        all_pass = False
    
    generate_test_vectors("test5_maxval", A_max, B_max)
    
    # ===== Summary =====
    print("\n" + "=" * 60)
    if all_pass:
        print("  >>> ALL VERIFICATION TESTS PASSED <<<")
    else:
        print("  >>> SOME TESTS FAILED <<<")
    print("=" * 60)
    
    return all_pass


def print_skew_pattern():
    """Visualize the staggered data feeding pattern."""
    print("\n" + "=" * 60)
    print("  Systolic Data Feeding Pattern (Skew Visualization)")
    print("=" * 60)
    
    N = 4
    model = SystolicArrayModel(array_size=N)
    
    A = np.array([
        [1, 2, 3, 4],
        [5, 6, 7, 8],
        [9, 10, 11, 12],
        [13, 14, 15, 16]
    ], dtype=np.int64)
    
    B = np.array([
        [1, 5, 9, 13],
        [2, 6, 10, 14],
        [3, 7, 11, 15],
        [4, 8, 12, 16]
    ], dtype=np.int64)
    
    a_inputs, b_inputs = model.generate_skewed_inputs(A, B)
    
    print(f"\n  Total feeding cycles: {len(a_inputs)}")
    print(f"  (N + K - 1 = {N} + {N} - 1 = {2*N - 1})")
    
    for c, (a, b) in enumerate(zip(a_inputs, b_inputs)):
        print(f"\n  Cycle {c}:")
        print(f"    A inputs (> rows): {a.tolist()}")
        print(f"    B inputs (v cols): {b.tolist()}")


if __name__ == "__main__":
    run_verification()
    print_skew_pattern()
