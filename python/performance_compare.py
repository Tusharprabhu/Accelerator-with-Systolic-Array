#!/usr/bin/env python3
"""
Performance Comparison: CPU vs Systolic Array Accelerator
=========================================================
Benchmarks matrix multiplication on CPU (Python/NumPy) and
estimates FPGA systolic array performance based on design parameters.

Generates performance metrics:
- Throughput (GOPS)
- Latency (cycles and time)
- Speedup over CPU
- Energy efficiency estimates
- Utilization analysis

Author: AI Accelerator Project
"""

import numpy as np
import time
import json
import os
from dataclasses import dataclass
from typing import Dict, List


@dataclass
class FPGAConfig:
    """FPGA accelerator configuration."""
    array_size: int = 4          # NxN systolic array
    data_width: int = 8          # INT8 operands
    acc_width: int = 32          # 32-bit accumulator
    clock_freq_mhz: float = 100.0  # Clock frequency (Basys3/Nexys)
    
    @property
    def total_pes(self) -> int:
        return self.array_size ** 2
    
    @property
    def peak_macs_per_cycle(self) -> int:
        return self.total_pes
    
    @property
    def peak_gops(self) -> float:
        """Peak GOPS = PEs × 2 ops/MAC × freq"""
        return (self.total_pes * 2 * self.clock_freq_mhz) / 1000.0


@dataclass
class BenchmarkResult:
    """Result of a single benchmark run."""
    matrix_size: int
    method: str
    time_seconds: float
    total_ops: int
    gops: float
    latency_cycles: int = 0
    
    def to_dict(self) -> dict:
        return {
            "matrix_size": self.matrix_size,
            "method": self.method,
            "time_seconds": self.time_seconds,
            "total_ops": self.total_ops,
            "gops": self.gops,
            "latency_cycles": self.latency_cycles
        }


def benchmark_python_naive(N: int, num_runs: int = 5) -> BenchmarkResult:
    """Benchmark naive Python matrix multiplication."""
    A = np.random.randint(0, 256, (N, N), dtype=np.int32)
    B = np.random.randint(0, 256, (N, N), dtype=np.int32)
    
    # Warm up
    _ = python_matmul(A, B)
    
    times = []
    for _ in range(num_runs):
        start = time.perf_counter()
        _ = python_matmul(A, B)
        end = time.perf_counter()
        times.append(end - start)
    
    avg_time = np.mean(times)
    total_ops = 2 * N * N * N  # N^3 multiplications + N^3 additions
    gops = total_ops / avg_time / 1e9
    
    return BenchmarkResult(
        matrix_size=N,
        method="Python (naive)",
        time_seconds=avg_time,
        total_ops=total_ops,
        gops=gops
    )


def python_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """Naive triple-loop matrix multiplication (no NumPy optimization)."""
    N = A.shape[0]
    C = np.zeros((N, N), dtype=np.int64)
    for i in range(N):
        for j in range(N):
            for k in range(N):
                C[i][j] += int(A[i][k]) * int(B[k][j])
    return C


def benchmark_numpy(N: int, num_runs: int = 10) -> BenchmarkResult:
    """Benchmark NumPy matrix multiplication."""
    A = np.random.randint(0, 256, (N, N), dtype=np.int32)
    B = np.random.randint(0, 256, (N, N), dtype=np.int32)
    
    # Warm up
    _ = A @ B
    
    times = []
    for _ in range(num_runs):
        start = time.perf_counter()
        _ = A @ B
        end = time.perf_counter()
        times.append(end - start)
    
    avg_time = np.mean(times)
    total_ops = 2 * N * N * N
    gops = total_ops / avg_time / 1e9
    
    return BenchmarkResult(
        matrix_size=N,
        method="NumPy (optimized)",
        time_seconds=avg_time,
        total_ops=total_ops,
        gops=gops
    )


def estimate_fpga_performance(N: int, config: FPGAConfig) -> BenchmarkResult:
    """
    Estimate FPGA systolic array performance.
    
    For NxN matrix multiplication with TxT systolic array:
    - Number of tiles per dimension: ceil(N/T)
    - Total tile computations: ceil(N/T)^3
    - Cycles per tile: T + T - 1 (pipeline fill) + overhead
    - Total cycles: tiles × cycles_per_tile + load/store overhead
    """
    T = config.array_size
    
    # Tiling
    num_tiles = int(np.ceil(N / T))
    total_tile_ops = num_tiles ** 3  # tiles along i, j, k
    
    # Cycles per tile computation
    pipeline_fill = T + T - 1  # Staggered feeding
    load_cycles = T * T * 2    # Load A tile + B tile
    store_cycles = T * T       # Store result tile
    compute_cycles = pipeline_fill
    
    # Total cycles
    total_cycles = total_tile_ops * (load_cycles + compute_cycles + store_cycles)
    
    # Add controller overhead (FSM transitions, etc.)
    overhead_factor = 1.15  # 15% overhead estimate
    total_cycles = int(total_cycles * overhead_factor)
    
    # Time calculation
    clock_period_ns = 1000.0 / config.clock_freq_mhz
    total_time_s = total_cycles * clock_period_ns * 1e-9
    
    # Operations
    total_ops = 2 * N * N * N
    gops = total_ops / total_time_s / 1e9 if total_time_s > 0 else 0
    
    return BenchmarkResult(
        matrix_size=N,
        method=f"FPGA Systolic ({T}x{T} @ {config.clock_freq_mhz}MHz)",
        time_seconds=total_time_s,
        total_ops=total_ops,
        gops=gops,
        latency_cycles=total_cycles
    )


def compute_utilization(N: int, config: FPGAConfig) -> Dict:
    """Compute PE utilization metrics."""
    T = config.array_size
    pipeline_fill = T + T - 1
    
    # During pipeline fill, not all PEs are active
    # Cycle 0: 1 PE active, Cycle 1: up to 2, ..., Cycle T-1: T PEs per row
    total_pe_cycles = 0
    for c in range(pipeline_fill):
        active_rows = min(c + 1, T)
        active_cols = min(c + 1, T)
        # Approximate: active PEs = min(c+1, T) * min(c+1, T) is upper bound
        # More accurate: count PEs that have valid data
        active_pes = 0
        for i in range(T):
            for j in range(T):
                if c >= i and c >= j and (c - i) < T and (c - j) < T:
                    active_pes += 1
        total_pe_cycles += active_pes
    
    max_pe_cycles = config.total_pes * pipeline_fill
    utilization = total_pe_cycles / max_pe_cycles if max_pe_cycles > 0 else 0
    
    return {
        "total_pes": config.total_pes,
        "pipeline_depth": pipeline_fill,
        "active_pe_cycles": total_pe_cycles,
        "max_pe_cycles": max_pe_cycles,
        "utilization_pct": utilization * 100,
        "peak_throughput_macs_per_cycle": config.peak_macs_per_cycle
    }


def run_benchmarks():
    """Run complete benchmark suite."""
    print("=" * 70)
    print("  Performance Comparison: CPU vs FPGA Systolic Array Accelerator")
    print("=" * 70)
    
    config = FPGAConfig(array_size=4, clock_freq_mhz=100.0)
    
    print(f"\n  FPGA Configuration:")
    print(f"    Array Size:     {config.array_size}x{config.array_size}")
    print(f"    Total PEs:      {config.total_pes}")
    print(f"    Data Width:     INT{config.data_width}")
    print(f"    Clock Freq:     {config.clock_freq_mhz} MHz")
    print(f"    Peak GOPS:      {config.peak_gops:.3f}")
    
    # Matrix sizes to benchmark
    sizes = [4, 8, 16, 32]
    
    results = []
    
    for N in sizes:
        print(f"\n{'-' * 70}")
        print(f"  Matrix Size: {N}x{N}")
        print(f"{'-' * 70}")
        
        # Python naive (skip for large sizes)
        if N <= 32:
            r_python = benchmark_python_naive(N, num_runs=3)
            results.append(r_python)
            print(f"  {r_python.method:30s}: {r_python.time_seconds:.6f}s | {r_python.gops:.6f} GOPS")
        
        # NumPy
        r_numpy = benchmark_numpy(N, num_runs=10)
        results.append(r_numpy)
        print(f"  {r_numpy.method:30s}: {r_numpy.time_seconds:.9f}s | {r_numpy.gops:.6f} GOPS")
        
        # FPGA estimate
        r_fpga = estimate_fpga_performance(N, config)
        results.append(r_fpga)
        print(f"  {r_fpga.method:30s}: {r_fpga.time_seconds:.9f}s | {r_fpga.gops:.6f} GOPS | {r_fpga.latency_cycles} cycles")
        
        # Speedup
        if N <= 32:
            speedup_vs_python = r_python.time_seconds / r_fpga.time_seconds if r_fpga.time_seconds > 0 else float('inf')
            print(f"  Speedup vs Python:  {speedup_vs_python:.1f}x")
        
        speedup_vs_numpy = r_numpy.time_seconds / r_fpga.time_seconds if r_fpga.time_seconds > 0 else float('inf')
        print(f"  Speedup vs NumPy:   {speedup_vs_numpy:.1f}x")
    
    # Utilization analysis
    print(f"\n{'=' * 70}")
    print(f"  PE Utilization Analysis")
    print(f"{'=' * 70}")
    
    util = compute_utilization(config.array_size, config)
    print(f"  Total PEs:                    {util['total_pes']}")
    print(f"  Pipeline Depth:               {util['pipeline_depth']} cycles")
    print(f"  Active PE-Cycles:             {util['active_pe_cycles']}")
    print(f"  Max PE-Cycles:                {util['max_pe_cycles']}")
    print(f"  Utilization:                  {util['utilization_pct']:.1f}%")
    print(f"  Peak Throughput:              {util['peak_throughput_macs_per_cycle']} MACs/cycle")
    
    # Data reuse analysis
    print(f"\n{'=' * 70}")
    print(f"  Data Reuse Analysis (Tiling Benefits)")
    print(f"{'=' * 70}")
    
    for N in [4, 8, 16, 32, 64]:
        T = config.array_size
        num_tiles = int(np.ceil(N / T))
        
        # Without tiling: need to load all of A and B every time
        naive_loads = 2 * N * N  # Load A + B entirely
        
        # With tiling: each tile of A is reused across column tiles of B
        # Each tile of B is reused across row tiles of A
        tiled_loads = num_tiles * (N * T + T * N)  # Simplified estimate
        
        # Actual: for each (i,j) output tile, load K tiles of A_row and K tiles of B_col
        actual_loads = num_tiles**2 * (2 * num_tiles * T * T)
        reuse_factor = naive_loads * num_tiles / actual_loads if actual_loads > 0 else 1
        
        print(f"  N={N:3d}: Tiles={num_tiles:2d}x{num_tiles:2d}x{num_tiles:2d} | "
              f"Naive loads={naive_loads:6d} | Tiled loads={actual_loads:6d}")
    
    # Save results
    save_results(results, util, config)
    
    return results


def save_results(results: List[BenchmarkResult], utilization: Dict, config: FPGAConfig):
    """Save benchmark results to files."""
    output_dir = os.path.join(os.path.dirname(__file__), "..", "results")
    os.makedirs(output_dir, exist_ok=True)
    
    # Throughput report
    with open(os.path.join(output_dir, "throughput.txt"), 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("  Throughput Report - Systolic Array Accelerator\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"FPGA Configuration:\n")
        f.write(f"  Array Size:  {config.array_size}x{config.array_size}\n")
        f.write(f"  Clock Freq:  {config.clock_freq_mhz} MHz\n")
        f.write(f"  Data Width:  INT{config.data_width}\n")
        f.write(f"  Peak GOPS:   {config.peak_gops:.3f}\n\n")
        
        f.write(f"{'Method':<35} {'Size':>6} {'GOPS':>12} {'Time (s)':>15}\n")
        f.write("-" * 70 + "\n")
        for r in results:
            f.write(f"{r.method:<35} {r.matrix_size:>4}x{r.matrix_size:<1} {r.gops:>12.6f} {r.time_seconds:>15.9f}\n")
    
    # Latency report
    with open(os.path.join(output_dir, "latency.txt"), 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("  Latency Report - Systolic Array Accelerator\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"{'Size':>6} {'Latency (cycles)':>18} {'Latency (us)':>15} {'Pipeline Fill':>15}\n")
        f.write("-" * 60 + "\n")
        for r in results:
            if "FPGA" in r.method:
                latency_us = r.time_seconds * 1e6
                pipeline = config.array_size + config.array_size - 1
                f.write(f"{r.matrix_size:>4}x{r.matrix_size:<1} {r.latency_cycles:>18} {latency_us:>15.3f} {pipeline:>15}\n")
    
    # Utilization report
    with open(os.path.join(output_dir, "utilization.txt"), 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("  Utilization Report - Systolic Array Accelerator\n")
        f.write("=" * 70 + "\n\n")
        for key, val in utilization.items():
            f.write(f"  {key}: {val}\n")
    
    # JSON export
    with open(os.path.join(output_dir, "benchmark_results.json"), 'w') as f:
        json.dump({
            "config": {
                "array_size": config.array_size,
                "data_width": config.data_width,
                "clock_freq_mhz": config.clock_freq_mhz,
                "peak_gops": config.peak_gops
            },
            "results": [r.to_dict() for r in results],
            "utilization": utilization
        }, f, indent=2)
    
    print(f"\n  Results saved to {output_dir}/")


if __name__ == "__main__":
    run_benchmarks()
