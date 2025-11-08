# MLX Metal Crash Debugging Summary

## Fixes Applied

### 1. Lazy Initialization (Swift & C++)
- ✅ Made `Stream.gpu/cpu` and `Device.gpu/cpu` lazy computed properties
- ✅ Made `device_info()` and `device()` lazy with mutex protection
- ✅ Changed default device from `.gpu` to `.cpu`

### 2. Runtime Guards
- ✅ Added environment variable checks in `device()` constructor
- ✅ Added device checking in `eval_impl()` dispatch path
- ✅ Added device logging in `array::eval()`
- ✅ Wrapped scoring in `Device.withDefaultDevice(Device.cpu)`

### 3. Diagnostics Added
- ✅ C++ logging in `device()` to catch Metal initialization
- ✅ Device logging in `array::eval()` and `eval_impl()`
- ✅ Stream device checking in `eval_impl()`

## Current Status

**Still crashing (exit code 138)** - Crash happens before logging appears, suggesting:
1. Crash occurs in C++ before reaching our guards
2. OR crash is in vDSP (Accelerate) CPU fallback with invalid memory
3. OR Metal is being called indirectly through a different path

## Next Steps: Use LLDB

### Setup LLDB Session

```bash
cd /Users/developer/mercatus
lldb .build/debug/SmartVestorCLI
```

### Set Breakpoints

```lldb
(lldb) b MTLCreateSystemDefaultDevice
(lldb) b MTLCreateSystemDefaultDeviceWithOptions
(lldb) b MTLCopyAllDevices
(lldb) b -n __metal_device
```

### Run and Get Backtrace

```lldb
(lldb) r coins --limit 3 --ml-based
```

When it stops (either at breakpoint or crash):

```lldb
(lldb) bt
(lldb) frame select 0
(lldb) disassemble
```

### If Breakpoints Don't Hit

The crash is likely in vDSP (Accelerate) CPU fallback:

```lldb
(lldb) image lookup -a $pc
(lldb) bt
```

Look for:
- `libvDSP.dylib` frames → CPU math kernel issue
- `libsystem_kernel.dylib` → Memory access violation
- `libdispatch.dylib` → Concurrency issue

### Expected Findings

1. **If Metal breakpoint hits**: See which MLX file calls Metal
   - Likely: `mlx/core/array/ops.cpp` or `mlx/core/array/math.cpp`
   - Fix: Add device check before GPU dispatch

2. **If vDSP crash**: Invalid memory access in CPU fallback
   - Likely: MLXArray with stale GPU layout passed to vDSP
   - Fix: Ensure arrays are properly converted to CPU before vDSP calls

3. **If no breakpoint**: Crash in initialization
   - Check: Static initializers we may have missed
   - Fix: Add more lazy initialization

## Files Modified

1. `.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/metal.cpp` - Lazy device_info()
2. `.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/device.cpp` - Lazy device() + guards
3. `.build/checkouts/mlx-swift/Source/MLX/Stream.swift` - Lazy Stream.gpu/cpu
4. `.build/checkouts/mlx-swift/Source/MLX/Device.swift` - Lazy Device.gpu/cpu + default CPU
5. `.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/array.cpp` - Device logging
6. `.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/transforms.cpp` - Device guards in eval_impl()
7. `Sources/SmartVestorCore/MLScoringEngine.swift` - CPU wrapping

## Environment Variables Set

- `MLX_DEVICE=cpu`
- `MLX_DISABLE_METAL=1`

These are set in `WorkingCLI.swift` for macOS 26 M3 Pro.

## Key Insight

The crash moved from **load-time** to **execution-time**, confirming static initializers are fixed. The remaining crash is in the **runtime dispatch path** where MLX decides GPU vs CPU, or in the **CPU fallback** (vDSP) itself.

LLDB backtrace will reveal the exact call site.
