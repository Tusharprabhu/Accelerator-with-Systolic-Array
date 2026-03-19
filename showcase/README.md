# 4x4 Matrix Multiplication Showcase

## Overview
This folder demonstrates a 4x4 matrix multiplication using the AI Accelerator with Systolic Array.

## Test Matrices

### Matrix A
```
[   1,    2,    3,    4]
[   5,    6,    7,    8]
[   9,   10,   11,   12]
[  13,   14,   15,   16]
```

### Matrix B
```
[   1,    2,    3,    4]
[   5,    6,    7,    8]
[   9,   10,   11,   12]
[  13,   14,   15,   16]
```

## Results

### Python Output:
```
Result C = A x B^T (Hardware Compatible):
  [  30,   70,  110,  150]
  [  70,  174,  278,  382]
  [ 110,  278,  446,  614]
  [ 150,  382,  614,  846]
```

### Verilog Output (Hardware):
```
Expected C:
  [    30,     70,    110,    150]
  [    70,    174,    278,    382]
  [   110,    278,    446,    614]
  [   150,    382,    614,    846]
Actual C:
  [    30,     70,    110,    150]
  [    70,    174,    278,    382]
  [   110,    278,    446,    614]
  [   150,    382,    614,    846]
```

## Comparison: MATCH ✓

## How to Run

### Python Reference Model
```bash
python showcase/reference.py
```

### Verilog Full Test Suite
```bash
cd sim
iverilog -o tb_accelerator_top.vvp ../rtl/pe.v ../rtl/systolic_array.v ../rtl/input_buffer.v ../rtl/output_buffer.v ../rtl/controller.v ../rtl/accelerator_top.v tb_accelerator_top.v
vvp tb_accelerator_top.vvp
```

## Architecture
- **Array Size**: 4x4 Processing Elements
- **Data Width**: 8-bit inputs
- **Accumulator**: 32-bit
- **Systolic Data Flow**: Row-wise for Matrix A, Column-wise for Matrix B
