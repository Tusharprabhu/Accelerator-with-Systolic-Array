#!/usr/bin/env python3
"""
4x4 Matrix Multiplication Reference Model
Simple showcase demonstration

The hardware reads B column-wise from row-major storage.
So hardware computes: A * (column-wise read B) = A * B_transposed
"""

def matmul_4x4(A, B):
    """Multiply A by B transposed (hardware behavior)"""
    C = [[0]*4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            for k in range(4):
                # Hardware reads B column-wise: B[j][k] becomes column j
                C[i][j] += A[i][k] * B[j][k]  # Use row j of B as column
    return C

def print_matrix(name, M):
    print(f"{name}:")
    for row in M:
        print(f"  [{row[0]:4d}, {row[1]:4d}, {row[2]:4d}, {row[3]:4d}]")

# Test matrices
A = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12],
    [13, 14, 15, 16]
]

B = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12],
    [13, 14, 15, 16]
]

print("=" * 50)
print("  4x4 Matrix Multiplication - Python Reference")
print("=" * 50)

print_matrix("Matrix A", A)
print_matrix("Matrix B (will be transposed for HW)", B)

C = matmul_4x4(A, B)

print_matrix("Result C = A x B^T (Hardware Compatible)", C)

print("=" * 50)
print("Hardware should output:")
print("  [  30,   70,  110,  150]")
print("  [  70,  174,  278,  382]")
print("  [ 110,  278,  446,  614]")
print("  [ 150,  382,  614,  846]")
print("=" * 50)
