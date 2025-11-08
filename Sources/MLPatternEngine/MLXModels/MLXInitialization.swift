import Foundation
#if os(macOS)
import Metal
import Darwin
#endif
import SmartVestorMLXAdapter
import MLX

public enum MLXInitialization {
    private nonisolated(unsafe) static var _isInitialized = false
    private nonisolated(unsafe) static var isConfigured = false
    private static let lock = NSLock()

    public static func configureMLX() {
        guard !isConfigured else { return }

        // Allow Metal by default - let it attempt initialization and fall back gracefully if it fails
        // Only force CPU mode if explicitly requested via environment variables
        #if os(macOS)
        let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"]
        let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"]

        if mlxDevice == "cpu" || disableMetal == "1" {
            print("[MLX] CPU mode requested via environment variables - forcing CPU")
            Device.withDefaultDevice(.cpu) {
                // No-op, just ensures CPU device is set
            }
            isConfigured = true
            return
        }
        #endif

        // Set default dtype to Float32 before any MLX types are created
        // Metal GPU doesn't support Float64, so we must use Float32

        // Note: MLX's defaultDType property may not be available in all versions
        // If available, use: MLX.defaultDType = .float32
        // Otherwise, create Float arrays early as fallback to establish Float32 context

        // Create Float tensors and operations early
        // This must happen BEFORE any Linear layers or other MLX types are created
        let a = MLXArray([Float(1.0), Float(2.0), Float(3.0)])
        let b = MLXArray([Float(4.0), Float(5.0), Float(6.0)])
        let c = a + b
        eval(c)

        // Force evaluation to ensure Float32 context is established
        // Use a scalar tensor for item() since it requires size == 1
        let scalar = MLXArray([Float(1.0)])
        eval(scalar)
        let _ = scalar.item(Float.self)

        isConfigured = true
    }

    public static func ensureInitialized() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !_isInitialized else { return }

        #if os(macOS)
        let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"]
        let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"]

        if (mlxDevice == "cpu" || disableMetal == "1") {
            throw MLXAdapter.InitError.invalidMetallib
        }
        #endif

        guard MLXAdapter.shouldUseGPU() else {
            throw MLXAdapter.InitError.invalidMetallib
        }

        guard MLXAdapter.metallibAvailable() else {
            throw MLXAdapter.InitError.invalidMetallib
        }

        #if os(macOS)
        if let debugLayer = ProcessInfo.processInfo.environment["MTL_DEBUG_LAYER"], debugLayer == "1" {
            print("Warning: MTL_DEBUG_LAYER enabled - GPU operations will be slower and may reveal issues")
        }
        #endif

        // Configure MLX dtype FIRST, before any operations
        configureMLX()

        try MLXAdapter.ensureInitialized()

        // Verify Float32 is working with a test array
        #if os(macOS)
        let testArray: [Float] = [1.0, 2.0, 3.0]
        let test = MLXArray(testArray)

        do {
            eval(test)

            // Verify test array is Float32
            guard test.dtype == MLX.DType.float32 else {
                throw MLXAdapter.InitError.invalidMetallib
            }

            // Test GPU operation with Float32
            let a = MLXArray([Float(1.0), Float(2.0), Float(3.0)])
            let b = MLXArray([Float(4.0), Float(5.0), Float(6.0)])
            let c = a + b
            eval(c)

            guard c.dtype == MLX.DType.float32 else {
                throw MLXAdapter.InitError.invalidMetallib
            }
        } catch {
            throw MLXAdapter.InitError.invalidMetallib
        }
        #else
        let testArray: [Float] = [1.0, 2.0, 3.0]
        let test = MLXArray(testArray)

        do {
            eval(test)

            // Verify test array is Float32
            guard test.dtype == MLX.DType.float32 else {
                throw MLXAdapter.InitError.invalidMetallib
            }

            // Test GPU operation with Float32
            let a = MLXArray([Float(1.0), Float(2.0), Float(3.0)])
            let b = MLXArray([Float(4.0), Float(5.0), Float(6.0)])
            let c = a + b
            eval(c)

            guard c.dtype == MLX.DType.float32 else {
                throw MLXAdapter.InitError.invalidMetallib
            }
        } catch {
            throw MLXAdapter.InitError.invalidMetallib
        }
        #endif

        _isInitialized = true
    }
}
