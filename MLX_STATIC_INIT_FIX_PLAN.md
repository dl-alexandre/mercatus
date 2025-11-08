# MLX Swift Static Initialization Fix Plan

## Problem Statement

MLX Swift crashes on macOS 26 M3 Pro due to Metal initialization happening at **library load time** via static initialization, before Swift code can prevent it by setting CPU mode.

### Root Cause Chain

1. **Static Initialization in `metal.cpp`** (line 80):
   ```cpp
   static auto device_info_ = init_device_info();  // Runs at library load!
   ```

2. **`init_device_info()` calls** (line 57):
   ```cpp
   auto raw_device = device(default_device()).mtl_device();
   ```

3. **`device()` returns static singleton** (device.cpp line 902):
   ```cpp
   static Device metal_device;  // Constructor runs at library load!
   return metal_device;
   ```

4. **`Device::Device()` constructor** (device.cpp line 351):
   ```cpp
   device_ = load_device();  // Calls MTL::CreateSystemDefaultDevice()
   default_library_ = load_default_library(device_);  // Loads Metal library
   ```

5. **Metal initializes before Swift can set CPU mode** → Crash on macOS 26 M3 Pro

## Solution Strategy

### Phase 1: Make `device_info()` Lazy (Defer Until First Call)

**Current Problem**: Static initialization runs immediately
**Fix**: Use lazy initialization with mutex protection

**File**: `Source/Cmlx/mlx/mlx/backend/metal/metal.cpp`

**Change**:
```cpp
const std::unordered_map<std::string, std::variant<std::string, size_t>>&
device_info() {
  static std::mutex init_mutex;
  static std::unique_ptr<std::unordered_map<std::string, std::variant<std::string, size_t>>> device_info_;

  // Double-checked locking pattern
  if (!device_info_) {
    std::lock_guard<std::mutex> lock(init_mutex);
    if (!device_info_) {
      auto init_device_info = []() -> ... {
        // Only initialize Metal device when actually called
        auto raw_device = device(default_device()).mtl_device();
        // ... rest of initialization
      };
      device_info_ = std::make_unique<...>(init_device_info());
    }
  }
  return *device_info_;
}
```

**Benefits**:
- Metal only initializes when `device_info()` is actually called
- Allows Swift to set CPU mode before first call
- Thread-safe lazy initialization

### Phase 2: Make `device()` Lazy (Defer Device Construction)

**Current Problem**: Static Device singleton constructs immediately
**Fix**: Use lazy initialization with once_flag

**File**: `Source/Cmlx/mlx/mlx/backend/metal/device.cpp`

**Change**:
```cpp
Device& device(mlx::core::Device) {
  static std::once_flag init_flag;
  static std::unique_ptr<Device> metal_device;

  std::call_once(init_flag, []() {
    // Check for CPU mode before initializing Metal
    #ifdef __APPLE__
    const char* mlx_device = std::getenv("MLX_DEVICE");
    if (mlx_device && std::string(mlx_device) == "cpu") {
      // Don't initialize Metal device if CPU mode requested
      // Return a CPU device instead (would need CPU Device implementation)
      return;
    }
    #endif

    metal_device = std::make_unique<Device>();
  });

  if (!metal_device) {
    // Return CPU device if Metal initialization was skipped
    // (Requires CPU Device implementation)
    throw std::runtime_error("Metal device not available, CPU mode required");
  }

  return *metal_device;
}
```

**Benefits**:
- Respects `MLX_DEVICE=cpu` environment variable
- Defers Metal initialization until first use
- Allows Swift to set environment before first call

### Phase 3: Add CPU Mode Check in Device Constructor

**Current Problem**: Device constructor always initializes Metal
**Fix**: Check environment variable before Metal initialization

**File**: `Source/Cmlx/mlx/mlx/backend/metal/device.cpp`

**Change**:
```cpp
Device::Device() {
  auto pool = new_scoped_memory_pool();

  #ifdef __APPLE__
  // Check for CPU mode before initializing Metal
  const char* mlx_device = std::getenv("MLX_DEVICE");
  const char* disable_metal = std::getenv("MLX_DISABLE_METAL");

  if ((mlx_device && std::string(mlx_device) == "cpu") ||
      (disable_metal && std::string(disable_metal) == "1")) {
    // Skip Metal initialization - would need CPU Device implementation
    throw std::runtime_error("CPU mode requested, Metal device not available");
  }

  // Check for macOS 26 M3 Pro (use existing is_macos26_m3_pro() function)
  if (is_macos26_m3_pro()) {
    // Skip Metal initialization on problematic platform
    throw std::runtime_error("macOS 26 M3 Pro detected, Metal initialization skipped");
  }
  #endif

  device_ = load_device();
  default_library_ = load_default_library(device_);
  // ... rest of constructor
}
```

**Benefits**:
- Respects environment variables
- Uses existing macOS 26 M3 Pro detection
- Prevents Metal initialization on problematic platform

### Phase 4: Add CPU Device Fallback (If Needed)

**Current Problem**: No CPU Device implementation in Metal backend
**Fix**: Either throw error (forcing Swift fallback) or implement CPU Device

**Option A**: Throw error (simpler, forces Swift-level fallback)
- Swift code catches error and uses CPU mode
- No C++ changes needed beyond error throwing

**Option B**: Implement CPU Device (more complex)
- Would require CPU Device implementation in Metal backend
- More work but better user experience

## Implementation Steps

### Step 1: Test Current Behavior
- [ ] Create minimal test that imports MLX Swift
- [ ] Verify crash happens at library load (before any Swift code runs)
- [ ] Document exact crash point (which static initializer)

### Step 2: Implement Lazy `device_info()`
- [ ] Modify `metal.cpp` to use lazy initialization
- [ ] Add mutex protection for thread safety
- [ ] Test that Metal doesn't initialize until `device_info()` is called
- [ ] Verify Swift can set CPU mode before first call

### Step 3: Implement Lazy `device()`
- [ ] Modify `device.cpp` to use lazy initialization
- [ ] Add environment variable checking
- [ ] Test that Metal doesn't initialize until `device()` is called
- [ ] Verify environment variables are respected

### Step 4: Add CPU Mode Check in Constructor
- [ ] Add environment variable checks in `Device::Device()`
- [ ] Add macOS 26 M3 Pro check (use existing function)
- [ ] Test that Metal initialization is skipped when appropriate
- [ ] Verify error is thrown (allowing Swift fallback)

### Step 5: Integration Testing
- [ ] Test with `MLX_DEVICE=cpu` environment variable
- [ ] Test on macOS 26 M3 Pro (should skip Metal)
- [ ] Test on other platforms (should work normally)
- [ ] Verify Swift fallback to CPU mode works

### Step 6: Contribute Back
- [ ] Create GitHub issue describing the problem
- [ ] Create pull request with fix
- [ ] Include test cases
- [ ] Document the change and rationale

## Testing Strategy

### Unit Tests
1. **Test lazy initialization**:
   - Verify `device_info()` doesn't initialize Metal until called
   - Verify `device()` doesn't initialize Metal until called

2. **Test environment variable handling**:
   - Set `MLX_DEVICE=cpu` and verify Metal isn't initialized
   - Set `MLX_DISABLE_METAL=1` and verify Metal isn't initialized

3. **Test macOS 26 M3 Pro detection**:
   - Mock `is_macos26_m3_pro()` to return true
   - Verify Metal initialization is skipped

### Integration Tests
1. **Test Swift integration**:
   - Import MLX Swift without crashing
   - Set CPU mode before any MLX operations
   - Verify fallback to CPU works

2. **Test on actual hardware**:
   - Test on macOS 26 M3 Pro (should not crash)
   - Test on other macOS versions (should work normally)
   - Test on other Apple Silicon (should work normally)

## Files to Modify

1. `Source/Cmlx/mlx/mlx/backend/metal/metal.cpp`
   - Make `device_info()` lazy
   - Add mutex protection

2. `Source/Cmlx/mlx/mlx/backend/metal/device.cpp`
   - Make `device()` lazy
   - Add environment variable checking
   - Add CPU mode check in constructor

3. `Source/Cmlx/mlx/mlx/backend/metal/device.h`
   - May need to add forward declarations if needed

## Risks and Mitigation

### Risk 1: Thread Safety
- **Risk**: Lazy initialization might have race conditions
- **Mitigation**: Use `std::once_flag` or mutex-protected double-checked locking

### Risk 2: Performance Impact
- **Risk**: Lazy initialization adds overhead
- **Mitigation**: Overhead is minimal (one-time check), benefits outweigh costs

### Risk 3: Breaking Changes
- **Risk**: Changes might break existing code
- **Mitigation**: Changes are internal, API remains the same

### Risk 4: CPU Device Not Available
- **Risk**: Throwing error might break some use cases
- **Mitigation**: Swift code handles error and falls back to CPU mode

## Success Criteria

1. ✅ MLX Swift can be imported without crashing on macOS 26 M3 Pro
2. ✅ `MLX_DEVICE=cpu` environment variable is respected
3. ✅ Metal initialization is deferred until first actual use
4. ✅ Swift code can set CPU mode before Metal initializes
5. ✅ Existing functionality works on other platforms
6. ✅ Fix can be contributed back to MLX Swift

## Next Steps

1. Create a test case that reproduces the crash
2. Implement lazy `device_info()` first (smallest change)
3. Test that it prevents the crash
4. Implement lazy `device()` if needed
5. Add environment variable checks
6. Create pull request with fix
