# Mercatus - Comprehensive Cryptocurrency Trading Platform

A production-ready cryptocurrency trading platform built in Swift, featuring real-time arbitrage detection, sophisticated statistical analysis, and automated portfolio management.

## 🏗️ Architecture Overview

Mercatus consists of three integrated components working together to provide comprehensive market analysis and automated trading:

### Core Components

**MLPatternEngine** - Production-ready ML framework with real-time inference
- Real-time price prediction with high-confidence models
- Comprehensive feature extraction (RSI, MACD, Bollinger Bands, volatility, momentum)
- Pattern recognition (400+ patterns per coin: cup-and-handle, head-and-shoulders, etc.)
- Volatility forecasting using GARCH models
- REST API with OpenAPI 3.0 specification and JWT authentication
- SQLite time-series storage with extensive historical data
- **MLX GPU Acceleration**: Optional Apple Silicon GPU acceleration (M3 Pro and later)

**SmartVestor** - Automated investment management with ML-powered scoring
- **🤖 ML-Powered Scoring (Default)**: Uses MLPatternEngine with real market data
- **Real-time Analysis**: Price prediction, volatility forecasting, pattern recognition
- **Performance Optimized**: Sub-second response times with intelligent caching
- Multi-dimensional scoring system (fundamental, momentum, technical, liquidity, volatility)
- Cross-exchange optimization with realistic fee modeling
- Dynamic rebalancing with configurable thresholds
- Risk management with stop-loss protection and portfolio limits
- Automated deposit monitoring and execution

**ArbitrageEngine** - Real-time arbitrage detection across exchanges
- Multi-exchange spread analysis (Kraken, Coinbase, Gemini)
- Real-time arbitrage opportunity detection
- Circuit breaker pattern for fault tolerance
- Performance monitoring and health checks

## 🚀 Quick Start

### Prerequisites
- macOS 13+ (14+ recommended for MLX GPU acceleration)
- Swift 6.2+
- Xcode Command Line Tools
- Docker (for MLPatternEngine production deployment)

### Build All Components
```bash
swift build
```

### Setup MLX GPU Acceleration (Optional, for M3 Pro and later)

**Important:** MLX's C++ core initializes at library load time, before any Swift code runs. The `default.metallib` file must exist in one of MLX's search paths before the executable starts, otherwise you'll see:

```
MLX error: Failed to load the default metallib. library not found
```

MLX searches for the metallib in this order:
1. Current working directory
2. Colocated with the executable (as `mlx.metallib` or `default.metallib`)
3. `~/.mlx/default.metallib`
4. `/usr/local/share/mlx/default.metallib`
5. `METAL_PATH` environment variable

**Recommended: Use the launcher script (easiest)**

The launcher script automatically ensures the metallib is in place before running:

```bash
# For debug builds
./scripts/run-smartvestor.sh debug coins --limit 5

# For release builds
./scripts/run-smartvestor.sh release coins --limit 5
```

**Alternative 1: Ensure metallib before `swift run`**

Run this before using `swift run`:

```bash
source scripts/ensure-mlx-metallib.sh
swift run SmartVestorCLI coins --limit 5
```

Or add to your `~/.zshrc` to make it automatic:

```bash
source /path/to/mercatus/scripts/smartvestor-shell-setup.sh
```

Then use `sv-run` instead of `swift run`:

```bash
sv-run SmartVestorCLI coins --limit 5
```

**Alternative 2: Build MLX metallib from sources**

The included `default.metallib` is a placeholder. You need to build the real MLX metallib:

```bash
./scripts/build-mlx-metallib.sh
```

This builds the MLX metallib from the checked-out MLX sources using CMake. Requires:
- `cmake` (install with `brew install cmake`)
- `ninja` (optional, install with `brew install ninja`)

**Alternative 3: Manual setup (one-time)**

If you have a valid MLX metallib, copy it:

```bash
cp /path/to/mlx.metallib Sources/SmartVestorMLXAdapter/Resources/default.metallib
./scripts/setup-mlx-metallib.sh
```

**Verify setup:**
```bash
strings Sources/SmartVestorMLXAdapter/Resources/default.metallib | grep -i rbitsc
```

If this command finds `rbitsc`, you have the correct metallib. If not, you need to build it from MLX sources.

**Troubleshooting "illegal hardware instruction" crashes:**

If you see this error after building the metallib:

```bash
zsh: illegal hardware instruction  swift run SmartVestorCLI coins --limit 1
```

This indicates a runtime issue with MLX's Metal backend, not a missing file. Try:

1. **Verify metallib and executable architectures match:**
   ```bash
   file Sources/SmartVestorMLXAdapter/Resources/default.metallib
   otool -hv .build/arm64-apple-macosx/debug/SmartVestorCLI | grep arm64
   ```
   Both should be `arm64` for Apple Silicon.

2. **Validate the metallib format:**
   ```bash
   file Sources/SmartVestorMLXAdapter/Resources/default.metallib
   ```
   Should show "MetalLib executable (MacOS)".

3. **Rebuild both in Release mode:**
   ```bash
   rm -rf .build/mlx-metallib-build
   ./scripts/build-mlx-metallib.sh
   swift build -c release
   swift run -c release SmartVestorCLI coins --limit 1
   ```

4. **Check MLX version mismatch:**
   Ensure the metallib was built from the same MLX commit as your Swift package:
   ```bash
   git -C .build/checkouts/mlx-swift log --oneline -1
   cat Package.resolved | grep -A3 "mlx-swift" | grep revision
   ```
   If you updated the MLX package, rebuild the metallib:
   ```bash
   swift package resolve --reset
   swift build
   ./scripts/build-mlx-metallib.sh
   ```

5. **Test CPU mode (isolate GPU issue):**
   ```bash
   env MLX_DEVICE=cpu swift run -c release SmartVestorCLI coins --limit 1
   ```
   If this works, the crash is isolated to Metal GPU path.

6. **Debug the crash with LLDB:**
   ```bash
   ./scripts/debug-mlx-crash.sh
   ```
   Or manually:
   ```bash
   lldb -- swift run -c release SmartVestorCLI coins --limit 1
   (lldb) run
   # When it crashes:
   (lldb) bt
   (lldb) disassemble -f
   ```

7. **Enable Metal validation:**
   ```bash
   env MTL_DEBUG_LAYER=1 MTL_ENABLE_DEBUG_INFO=1 swift run -c release SmartVestorCLI coins --limit 1
   ```

8. **Disable GPU completely (use rule-based):**
   ```bash
   env SV_DISABLE_GPU=1 swift run SmartVestorCLI coins --limit 1
   ```

9. **Test minimal MLX repro:**
   ```bash
   swift scripts/test-mlx-minimal.swift
   ```
   If this crashes, report to MLX Swift.

10. **Generate bug report info:**
    ```bash
    ./scripts/generate-mlx-bug-report.sh
    ```
    This prints all diagnostic information needed for the MLX Swift bug report.

    **Bug Report Template:**
    See `docs/MLX_BUG_REPORT.md` for a complete bug report template with:
    - Environment details
    - MLX commit hash
    - Metallib hash
    - LLDB backtrace instructions
    - Minimal reproduction code

**Note:** MLX GPU acceleration requires:
- Apple Silicon (M1/M2/M3 or later)
- macOS 14+ for optimal performance
- Metal-compatible GPU
- Matching metallib and MLX Swift package versions

## 📚 Documentation

For comprehensive documentation including:
- Detailed architecture overview
- API documentation
- Deployment guides
- Testing strategies
- Performance analysis

See the [`docs/`](./docs/) directory and start with [`docs/README.md`](./docs/README.md).

### Run SmartVestor CLI

**Without MLX (no GPU acceleration):**
```bash
swift run SmartVestorCLI coins --limit 5
```

**With MLX (use launcher to ensure metallib is available):**
```bash
./scripts/run-smartvestor.sh debug coins --limit 5
```
