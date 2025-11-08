# MLX Swift Lazy Initialization Fix

## Problem Found

**Root Cause**: Swift static properties initialize at module load time, triggering Metal initialization before the app can set CPU mode.

### Culprits Identified

1. **`Stream.swift` line 86**: `public static let gpu = Stream(mlx_default_gpu_stream_new())`
   - Initialized when MLX module is imported
   - Calls `mlx_default_gpu_stream_new()` → `mlx::core::default_stream(Device::gpu)` → triggers Metal

2. **`Stream.swift` line 52**: `public static let gpu = device(.gpu)` in `StreamOrDevice`
   - Initialized when MLX module is imported
   - Calls `device(.gpu)` → `Device.gpu` → triggers Metal

3. **`Device.swift` line 81**: `static public let gpu: Device = Device(.gpu)`
   - Initialized when MLX module is imported
   - Calls `Device(.gpu)` → `mlx_device_new_type(MLX_GPU)` → triggers Metal

## Fix Applied

### 1. Made `Stream.gpu` and `Stream.cpu` Lazy

**File**: `.build/checkouts/mlx-swift/Source/MLX/Stream.swift`

**Before**:
```swift
public static let gpu = Stream(mlx_default_gpu_stream_new())
public static let cpu = Stream(mlx_default_cpu_stream_new())
```

**After**:
```swift
private static let _gpuLock = NSLock()
private static var _gpu: Stream?
public static var gpu: Stream {
    _gpuLock.lock()
    defer { _gpuLock.unlock() }
    if _gpu == nil {
        _gpu = Stream(mlx_default_gpu_stream_new())
    }
    return _gpu!
}

private static let _cpuLock = NSLock()
private static var _cpu: Stream?
public static var cpu: Stream {
    _cpuLock.lock()
    defer { _cpuLock.unlock() }
    if _cpu == nil {
        _cpu = Stream(mlx_default_cpu_stream_new())
    }
    return _cpu!
}
```

### 2. Made `Device.gpu` and `Device.cpu` Lazy

**File**: `.build/checkouts/mlx-swift/Source/MLX/Device.swift`

**Before**:
```swift
static public let cpu: Device = Device(.cpu)
static public let gpu: Device = Device(.gpu)
```

**After**:
```swift
private static let _cpuLock = NSLock()
private static var _cpu: Device?
static public var cpu: Device {
    _cpuLock.lock()
    defer { _cpuLock.unlock() }
    if _cpu == nil {
        _cpu = Device(.cpu)
    }
    return _cpu!
}

private static let _gpuLock = NSLock()
private static var _gpu: Device?
static public var gpu: Device {
    _gpuLock.lock()
    defer { _gpuLock.unlock() }
    if _gpu == nil {
        _gpu = Device(.gpu)
    }
    return _gpu!
}
```

### 3. Made `StreamOrDevice.gpu` and `StreamOrDevice.cpu` Lazy

**File**: `.build/checkouts/mlx-swift/Source/MLX/Stream.swift`

**Before**:
```swift
public static let cpu = device(.cpu)
public static let gpu = device(.gpu)
```

**After**:
```swift
public static var cpu: StreamOrDevice {
    device(.cpu)
}

public static var gpu: StreamOrDevice {
    device(.gpu)
}
```

## Benefits

1. **No Metal initialization at library load** - Properties are only initialized when accessed
2. **CPU mode can be set before GPU access** - App can set `MLX_DISABLE_METAL=1` before any GPU property is accessed
3. **Thread-safe lazy initialization** - Uses `NSLock` to prevent race conditions
4. **Backward compatible** - API remains the same, just lazy instead of eager

## Testing

Run the minimal test:
```bash
swift test_mlx_lazy_init.swift
```

Expected output:
- No crash at `import MLX`
- Successful import message
- CPU device accessible
- GPU device fails gracefully in CPU mode

## Combined with Previous Fixes

This fix works together with:

1. **Lazy `device_info()`** - C++ level lazy initialization
2. **Lazy `device()`** - C++ level lazy initialization with environment checks
3. **Device constructor checks** - Environment variable and macOS 26 M3 Pro checks

## Next Steps

1. Test on macOS 26 M3 Pro hardware
2. Verify no crash at library load
3. Verify CPU mode works correctly
4. Create GitHub issue and PR
