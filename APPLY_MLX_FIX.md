# Apply MLX Fix to Fork

## Changes Made

The fix has been applied to the MLX source in `.build/checkouts/mlx-swift`. To make this permanent:

## Step 1: Fork MLX Swift
```bash
# Go to https://github.com/ml-explore/mlx-swift and click Fork
```

## Step 2: Clone Your Fork
```bash
cd ~
git clone https://github.com/YOUR_USERNAME/mlx-swift.git mlx-swift-fork
cd mlx-swift-fork
git checkout -b fix/macos26-m3pro-sigill
```

## Step 3: Apply the Patch
```bash
# Copy the patch from mercatus
cp /Users/developer/mercatus/mlx-fix.patch ~/mlx-swift-fork/

# Apply it
cd ~/mlx-swift-fork
git apply mlx-fix.patch

# Or manually apply the changes from the files in .build/checkouts/mlx-swift
```

## Step 4: Build and Test
```bash
cd ~/mlx-swift-fork
swift build
```

## Step 5: Update Package.swift to Use Your Fork
```swift
// In /Users/developer/mercatus/Package.swift, change:
.package(url: "https://github.com/ml-explore/mlx-swift.git", branch: "main")

// To:
.package(url: "https://github.com/YOUR_USERNAME/mlx-swift.git", branch: "fix/macos26-m3pro-sigill")
```

## Step 6: Test in Mercatus
```bash
cd /Users/developer/mercatus
swift package resolve
./scripts/build-mlx-metallib.sh
swift run SmartVestorCLI coins --limit 1
```

## Step 7: Create PR
```bash
cd ~/mlx-swift-fork
git add .
git commit -m "Fix: Handle SIGILL on macOS 26 M3 Pro

Add runtime detection and safer Metal compute pipeline creation
for macOS 26.0.1 on Apple M3 Pro to prevent illegal hardware
instruction crashes.

Changes:
- Added is_macos26_m3_pro() detection function
- Modified get_kernel_() to use safer pipeline options on M3 Pro
- Added threadgroup size validation in dispatch_threads()
- Added threadgroup limits in RBits::eval_gpu()

Fixes crash on macOS 26.0.1 (Build 25A362), Apple M3 Pro (arm64)"
git push origin fix/macos26-m3pro-sigill
```

Then create PR on GitHub.
