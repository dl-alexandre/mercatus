import Foundation
#if os(macOS)
import Metal
#endif
import Darwin

private let _mlxMetallibSetup: Void = {
    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser
    let mlxDir = homeDir.appendingPathComponent(".mlx")
    let mlxTarget = mlxDir.appendingPathComponent("default.metallib")

    var sourceMetallib: URL?

    if let bundleURL = Bundle.module.url(forResource: "default", withExtension: "metallib") {
        sourceMetallib = bundleURL
    } else if let resourcePath = Bundle.module.resourcePath {
        let candidate = URL(fileURLWithPath: resourcePath).appendingPathComponent("default.metallib")
        if fileManager.fileExists(atPath: candidate.path) {
            sourceMetallib = candidate
        }
    }

    guard let source = sourceMetallib, fileManager.fileExists(atPath: source.path) else {
        return
    }

    if !fileManager.fileExists(atPath: mlxTarget.path) {
        try? fileManager.createDirectory(at: mlxDir, withIntermediateDirectories: true)
        try? fileManager.copyItem(at: source, to: mlxTarget)
    }

    let cwd = fileManager.currentDirectoryPath
    let cwdTarget = URL(fileURLWithPath: cwd).appendingPathComponent("default.metallib")
    if !fileManager.fileExists(atPath: cwdTarget.path) {
        try? fileManager.copyItem(at: source, to: cwdTarget)
    }

    let executablePath = ProcessInfo.processInfo.arguments.first ?? ""
    if !executablePath.isEmpty {
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let execTarget = URL(fileURLWithPath: executableDir).appendingPathComponent("default.metallib")
        if !fileManager.fileExists(atPath: execTarget.path) {
            try? fileManager.copyItem(at: source, to: execTarget)
        }
    }
}()

public enum MLXAdapter {
    private nonisolated(unsafe) static var once = false
    private static let lock = NSLock()
    private nonisolated(unsafe) static var errorHandlerSet = false

    public enum InitError: Error {
        case noMetal
        case metallibNotFound
        case invalidMetallib
    }

    private static func setCustomErrorHandler() {
        guard !errorHandlerSet else { return }
        errorHandlerSet = true

        #if os(macOS) && canImport(MLX)
        let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"]
        let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"]

        if mlxDevice == "cpu" || disableMetal == "1" {
            // Error handler is set in WorkingCLI.swift at module load time
            // This function is kept for compatibility but the actual handler
            // is set earlier in _forceMLXAdapterLoad
        }
        #endif
    }

    public static func shouldUseGPU() -> Bool {
        if ProcessInfo.processInfo.environment["SV_DISABLE_GPU"] == "1" {
            return false
        }

        if ProcessInfo.processInfo.environment["MLX_DEVICE"] == "cpu" {
            return false
        }

        if ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"] == "1" {
            return false
        }

        #if os(macOS)
        // Try to create Metal device - if it fails, we'll fall back gracefully
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[MLX] No Metal device available - using CPU")
            return false
        }

        let vendorName = device.name
        if vendorName.contains("Intel") || vendorName.contains("AMD") {
            print("[MLX] Intel/AMD GPU detected - using CPU (Apple Silicon required)")
            return false
        }

        if ProcessInfo.processInfo.environment["MTL_DEBUG_LAYER"] == "1" {
            print("Warning: Metal debug layer enabled - GPU operations may be slower")
        }

        print("[MLX] Metal device available: \(vendorName) - attempting GPU acceleration")
        return true
        #else
        return false
        #endif
    }

    public static func metallibAvailable() -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let mlxPath = homeDir.appendingPathComponent(".mlx/default.metallib")

        if FileManager.default.fileExists(atPath: mlxPath.path) {
            if let data = try? Data(contentsOf: mlxPath) {
                let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) ?? ""
                if string.localizedCaseInsensitiveContains("rbitsc") || data.count > 1000 {
                    return true
                }
            }
        }

        let executablePath = ProcessInfo.processInfo.arguments.first ?? ""
        if !executablePath.isEmpty {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            let execPath = URL(fileURLWithPath: executableDir).appendingPathComponent("mlx.metallib")
            if FileManager.default.fileExists(atPath: execPath.path) {
                if let data = try? Data(contentsOf: execPath) {
                    let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) ?? ""
                    if string.localizedCaseInsensitiveContains("rbitsc") || data.count > 1000 {
                        return true
                    }
                }
            }

            let execPathDefault = URL(fileURLWithPath: executableDir).appendingPathComponent("default.metallib")
            if FileManager.default.fileExists(atPath: execPathDefault.path) {
                if let data = try? Data(contentsOf: execPathDefault) {
                    let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) ?? ""
                    if string.localizedCaseInsensitiveContains("rbitsc") || data.count > 1000 {
                        return true
                    }
                }
            }
        }

        let cwd = FileManager.default.currentDirectoryPath
        let cwdPath = URL(fileURLWithPath: cwd).appendingPathComponent("default.metallib")
        if FileManager.default.fileExists(atPath: cwdPath.path) {
            if let data = try? Data(contentsOf: cwdPath) {
                let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) ?? ""
                if string.localizedCaseInsensitiveContains("rbitsc") || data.count > 1000 {
                    return true
                }
            }
        }

        return false
    }

    public static func ensureInitialized() throws {
    lock.lock()
    defer { lock.unlock() }

    guard !once else { return }

    #if os(macOS)
    // Try Metal initialization - errors will be caught and handled gracefully
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("[MLX] No Metal device available")
        throw InitError.noMetal
    }

    print("[MLX] Metal device found: \(device.name)")

    let executablePath = ProcessInfo.processInfo.arguments.first ?? ""
    let executableDir = (executablePath as NSString).deletingLastPathComponent
    let targetPath = (executableDir as NSString).appendingPathComponent("default.metallib")

    func validateMetallib(at url: URL) -> Bool {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if fileSize < 1000 {
            return false
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }

        let searchBytes = "rbitsc".data(using: .ascii) ?? Data()
        guard !searchBytes.isEmpty else { return false }

        let chunkSize = 1024 * 1024
        var offset: UInt64 = 0

        while offset < fileSize {
            fileHandle.seek(toFileOffset: offset)
            guard let chunk = try? fileHandle.read(upToCount: chunkSize) else { break }

            if chunk.range(of: searchBytes) != nil {
                return true
            }

            offset += UInt64(chunk.count)
            if chunk.count < chunkSize {
                break
            }
        }

        return false
    }

    var metallibURL: URL?

    if let bundleURL = Bundle.module.url(forResource: "default", withExtension: "metallib"),
       validateMetallib(at: bundleURL) {
        metallibURL = bundleURL
        print("[MLX] Using metallib from bundle resource")
    } else if let bundlePath = Bundle.module.resourcePath {
        let bundleMetallib = URL(fileURLWithPath: bundlePath).appendingPathComponent("default.metallib")
        print("[MLX] Checking bundle metallib at: \(bundleMetallib.path)")
        print("[MLX] File exists: \(FileManager.default.fileExists(atPath: bundleMetallib.path))")
        if FileManager.default.fileExists(atPath: bundleMetallib.path) {
            print("[MLX] Validating bundle metallib...")
            if validateMetallib(at: bundleMetallib) {
                metallibURL = bundleMetallib
                print("[MLX] Using metallib from bundle directory")
            } else {
                print("[MLX] Bundle metallib validation failed")
            }
        }
    }

    if metallibURL == nil {
        let sourceMetallib = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("default.metallib")

        if FileManager.default.fileExists(atPath: sourceMetallib.path),
           validateMetallib(at: sourceMetallib) {
            metallibURL = sourceMetallib
            print("[MLX] Using metallib from source Resources directory")
        } else if FileManager.default.fileExists(atPath: targetPath),
                  validateMetallib(at: URL(fileURLWithPath: targetPath)) {
            metallibURL = URL(fileURLWithPath: targetPath)
            print("[MLX] Using metallib from executable directory")
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            let cwdPath = URL(fileURLWithPath: cwd).appendingPathComponent("default.metallib")
            if FileManager.default.fileExists(atPath: cwdPath.path),
               validateMetallib(at: cwdPath) {
                metallibURL = cwdPath
                print("[MLX] Using metallib from current directory")
            }
        }
    }

    guard let finalMetallibURL = metallibURL else {
        print("Error: Could not find valid metallib with rbitsc kernel")
        print("Error: Bundle.module.bundleURL = \(Bundle.module.bundleURL)")
        print("Error: Bundle.module.resourcePath = \(Bundle.module.resourcePath ?? "nil")")
        throw InitError.metallibNotFound
    }

    // Ensure metallib is in executable directory for METAL_PATH
    // MLX looks for metallib in multiple locations:
    // 1. "mlx.metallib" in executable directory (colocated)
    // 2. "Resources/mlx.metallib"
    // 3. SwiftPM "default.metallib"
    // 4. METAL_PATH/default.metallib
    do {
        let mlxMetallibPath = (executableDir as NSString).appendingPathComponent("mlx.metallib")

        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(atPath: targetPath)
        }
        if FileManager.default.fileExists(atPath: mlxMetallibPath) {
            try FileManager.default.removeItem(atPath: mlxMetallibPath)
        }

        try FileManager.default.copyItem(at: finalMetallibURL, to: URL(fileURLWithPath: targetPath))
        try FileManager.default.copyItem(at: finalMetallibURL, to: URL(fileURLWithPath: mlxMetallibPath))

        print("[MLX] Copied validated metallib to executable directory:")
        print("[MLX]   - \(targetPath)")
        print("[MLX]   - \(mlxMetallibPath)")

        let copiedSize = (try? FileManager.default.attributesOfItem(atPath: targetPath)[.size] as? Int64) ?? 0
        print("[MLX] Copied metallib size: \(copiedSize) bytes")
    } catch {
        print("[MLX] Warning: Failed to copy metallib to executable directory: \(error.localizedDescription)")
        throw InitError.metallibNotFound
    }

    setenv("METAL_PATH", executableDir, 1)
    print("[MLX] Set METAL_PATH to: \(executableDir)")

    do {
            // Try to make library from the URL
            let library = try device.makeLibrary(URL: finalMetallibURL)
            _ = library
        } catch {
            // If that fails, try bundle if available
            do {
                let library = try device.makeDefaultLibrary(bundle: .module)
                _ = library
            } catch {
                throw InitError.invalidMetallib
            }
        }

        once = true
        #else
        throw InitError.noMetal
        #endif
    }
}
