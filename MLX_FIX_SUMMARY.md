# MLX Swift Static Initialization Fix - Summary & Contribution Plan

## Problem Analysis

### Root Cause
MLX Swift's Metal backend initializes Metal at **library load time** via static initialization, before Swift code can prevent it. This causes crashes on macOS 26 M3 Pro.

### Static Initialization Chain
1. **`metal.cpp:80`** - `static auto device_info_ = init_device_info()` runs at library load
2. **`metal.cpp:57`** - Calls `device(default_device()).mtl_device()`
3. **`device.cpp:902`** - `static Device metal_device` constructor runs at library load
4. **`device.cpp:353`** - `Device::Device()` calls `load_device()` → `MTL::CreateSystemDefaultDevice()`
5. **Metal initializes** → Crash on macOS 26 M3 Pro

### Why Existing Fixes Don't Work
- **Kernel-level fixes** (blocking `rbitsc`) don't prevent Metal initialization
- **Swift-level checks** run too late - Metal already initialized
- **Environment variables** (`MLX_DEVICE=cpu`) aren't checked before static initialization
- **Lazy initialization** helps, but something still triggers it during library import

## Fixes Implemented

### 1. Lazy `device_info()` ✅
**File**: `metal.cpp`
- Changed from `static auto device_info_ = init_device_info()` to lazy initialization with mutex
- Metal only initializes when `device_info()` is actually called
- Allows Swift to set CPU mode before first call

### 2. Lazy `device()` ✅
**File**: `device.cpp`
- Changed from `static Device metal_device` to `static std::unique_ptr<Device> metal_device` with lazy initialization
- Added environment variable checks (`MLX_DEVICE`, `MLX_DISABLE_METAL`)
- Added macOS 26 M3 Pro check using existing `is_macos26_m3_pro()` function
- Throws error if CPU mode requested, allowing Swift fallback

### 3. Device Constructor Checks ✅
**File**: `device.cpp` - `Device::Device()`
- Added environment variable checks before Metal initialization
- Added macOS 26 M3 Pro check before Metal initialization
- Throws error if Metal initialization should be skipped

## Remaining Issue

**Problem**: Crash still occurs even after fixes
- Swift detects macOS 26 M3 Pro and sets environment variables
- Factory falls back to traditional models
- But crash happens during scoring process

**Hypothesis**:
- Importing MLX Swift library triggers static initialization
- Even if we don't use MLX models, the library import itself causes Metal initialization
- Need to prevent MLX Swift import entirely on macOS 26 M3 Pro, or find other static initializers

## Next Steps for Contribution

### Step 1: Identify All Static Initializers
- [ ] Search for all `static` variables in Metal backend
- [ ] Check for global constructors that might initialize Metal
- [ ] Verify if `load_device()` or `MTL::CopyAllDevices()` are called elsewhere

### Step 2: Test Minimal Reproduction
- [ ] Create minimal test that imports MLX Swift without using it
- [ ] Verify if crash happens at import time or first use
- [ ] Document exact crash point

### Step 3: Complete Fix
- [ ] Ensure all Metal initialization is deferred until first use
- [ ] Add comprehensive environment variable checks
- [ ] Test on macOS 26 M3 Pro hardware

### Step 4: Create Pull Request
- [ ] Fork `ml-explore/mlx-swift`
- [ ] Create branch `fix/defer-metal-initialization`
- [ ] Implement fixes
- [ ] Add test cases
- [ ] Document the change

### Step 5: Create GitHub Issue
- [ ] Title: "Metal initialization at library load time causes crashes on macOS 26 M3 Pro"
- [ ] Description: Document the problem, root cause, and proposed fix
- [ ] Include crash logs and system information
- [ ] Link to pull request

## Files Modified

1. **`.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/metal.cpp`**
   - Made `device_info()` lazy
   - Added mutex protection

2. **`.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/device.cpp`**
   - Made `device()` lazy
   - Added environment variable checks
   - Added macOS 26 M3 Pro check in constructor

## Testing Strategy

### Unit Tests
- Test lazy initialization doesn't initialize Metal until called
- Test environment variables are respected
- Test macOS 26 M3 Pro detection prevents Metal initialization

### Integration Tests
- Test MLX Swift can be imported without crashing on macOS 26 M3 Pro
- Test CPU mode fallback works correctly
- Test normal operation on other platforms

## Contribution Checklist

- [x] Identify root cause
- [x] Implement lazy initialization fixes
- [ ] Identify remaining static initializers
- [ ] Create minimal reproduction test
- [ ] Complete fix
- [ ] Test on macOS 26 M3 Pro hardware
- [ ] Create GitHub issue
- [ ] Create pull request
- [ ] Get code review
- [ ] Merge to upstream

## Key Insights

1. **Static initialization is the enemy** - Any static initialization that touches Metal will crash on macOS 26 M3 Pro
2. **Lazy initialization is the solution** - Defer all Metal initialization until first actual use
3. **Environment variables must be checked early** - Before any Metal API calls
4. **Swift-level checks are too late** - Need C++ level checks before Metal initialization
5. **Library import triggers initialization** - Even importing MLX Swift can trigger static initialization

## References

- Fork: `dl-alexandre/mlx-swift` branch `fix/macos26-m3pro-sigill`
- Related issues: #82 (SIGBUS crash), #104 (macOS Sequoia beta crash)
- Metal documentation: [Apple Metal Documentation](https://developer.apple.com/metal/)
