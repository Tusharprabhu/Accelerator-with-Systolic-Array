# Systolic Array Matrix Multiply Accelerator

An end-to-end matrix-multiply accelerator built around a systolic-array style compute core. The repo includes a reference model for correctness, simulation testbenches, and scripts that generate the performance reports.

Key outcome: the accelerator outputs match the golden reference in simulation, and the results below are measured from the included scripts.

## Repository layout

| Path | Purpose |
|---|---|
| `rtl/` | Hardware design (compute core, buffers, top-level) |
| `sim/` | Simulation testbenches and test vectors |
| `python/` | Reference model and benchmark script |
| `results/` | Saved reports (text + JSON) |

## Results (4x4 array @ 100 MHz)

### Latency

| Matrix size | Latency (cycles) | Latency (us) |
|---:|---:|---:|
| 4x4 | 63 | 0.630 |
| 8x8 | 505 | 5.050 |
| 16x16 | 4047 | 40.470 |
| 32x32 | 32383 | 323.830 |

### Throughput (measured)

| Matrix size | Accelerator GOPS | Time (s) |
|---:|---:|---:|
| 4x4 | 0.203 | 0.000000630 |
| 8x8 | 0.203 | 0.000005050 |
| 16x16 | 0.202 | 0.000040470 |
| 32x32 | 0.202 | 0.000323830 |

For these sizes, naive Python reports ~0.00253 GOPS, which is about **80x slower** than the accelerator results above.

### Utilization

| Metric | Value |
|---|---:|
| Total compute elements | 16 |
| Active utilization | 39.3% |

## Full report files

| File | Description |
|---|---|
| `results/latency.txt` | Latency report |
| `results/throughput.txt` | Throughput report |
| `results/utilization.txt` | Utilization report |
| `results/benchmark_results.json` | Machine-readable summary |
