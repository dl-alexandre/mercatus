#!/usr/bin/env swift

import Foundation

setenv("MLX_DISABLE_METAL", "1", 1)
setenv("MLX_DEVICE", "cpu", 1)

print("[TEST] Environment variables set")
print("[TEST] MLX_DISABLE_METAL=\(getenv("MLX_DISABLE_METAL") != nil ? "1" : "nil")")
print("[TEST] MLX_DEVICE=\(String(cString: getenv("MLX_DEVICE") ?? "nil"))")

print("[TEST] About to import MLX...")

import MLX

print("[TEST] MLX imported successfully - no crash!")

print("[TEST] Accessing Device.cpu (should be lazy)...")
let _ = Device.cpu
print("[TEST] Device.cpu accessed successfully")

print("[TEST] Accessing Device.gpu (should be lazy, but will fail in CPU mode)...")
do {
    let _ = Device.gpu
    print("[TEST] Device.gpu accessed (unexpected - should have failed)")
} catch {
    print("[TEST] Device.gpu failed as expected: \(error)")
}

print("[TEST] SUCCESS - No crash at library load time!")
