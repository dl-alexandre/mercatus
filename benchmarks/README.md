# TUI Benchmark Baselines

This directory contains performance benchmark results for the TUI rendering system.

## Files

- `bench_baseline.json` - Reference baseline for CI threshold checks
- `bench_YYYY-MM-DD.json` - Dated benchmark runs for trend tracking
- `bench.log` - Latest benchmark output log

## Metrics

### P95 Render Latency
- **Target**: < 50 ms
- **Baseline**: See `bench_baseline.json`
- **CI Check**: Fails if ≥ 50 ms

### Changed Lines Percentage
- **Target**: ≤ 15%
- **Baseline**: See `bench_baseline.json`
- **CI Check**: Fails if > 15%

### Bytes per Second
- **Target**: < 64 KB/s under heavy updates
- **Baseline**: See `bench_baseline.json`

## Running Benchmarks

```bash
# Default (120x40, 30s)
swift run SmartVestorCLI tui-bench

# Custom duration and size
swift run SmartVestorCLI tui-bench --width 120 --height 40 --duration 10

# Results are written to:
# - bench_results.json (current directory)
# - benchmarks/bench_YYYY-MM-DD.json (dated copy)
```

## CI Integration

The `.github/workflows/tui-bench.yml` workflow runs benchmarks on:
- Pull requests that modify TUI code
- Pushes to main branch

Thresholds are enforced:
- P95 latency must be < 50 ms
- Changed lines must be ≤ 15%

## Updating Baseline

When performance improves or thresholds change:

```bash
cp benchmarks/bench_YYYY-MM-DD.json benchmarks/bench_baseline.json
git add benchmarks/bench_baseline.json
git commit -m "Update TUI benchmark baseline"
```

## Notes

- Benchmarks use synthetic price data with seeded RNG for determinism
- Buffer-based rendering path (`SMARTVESTOR_TUI_BUFFER=1`) is automatically enabled
- Results may vary based on system load and hardware
