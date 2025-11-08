import Foundation

public actor AssetScaleRegistry {
    private var scales: [String: Int] = [:]
    private var locked: Bool = false

    public init() {
        scales["BTC"] = 8
        scales["ETH"] = 8
        scales["USDC"] = 6
        scales["USDT"] = 6
        scales["DEFAULT"] = 8
    }

    public func getScale(for asset: String) -> Int {
        return scales[asset.uppercased()] ?? scales["DEFAULT"] ?? 8
    }

    public func setScale(_ scale: Int, for asset: String, migrationMode: Bool = false) throws {
        guard migrationMode || !locked else {
            throw SmartVestorError.configurationError("Scale registry is locked. Use migration mode to change scales.")
        }

        guard scale >= 0 && scale <= 18 else {
            throw SmartVestorError.configurationError("Invalid scale: must be between 0 and 18")
        }

        scales[asset.uppercased()] = scale
    }

    public func lock() {
        locked = true
    }

    public func unlock() {
        locked = false
    }

    public func getAllScales() -> [String: Int] {
        return scales
    }
}

extension AssetScale {
    private nonisolated(unsafe) static var registry: AssetScaleRegistry?

    public static func initializeRegistry() -> AssetScaleRegistry {
        let reg = AssetScaleRegistry()
        registry = reg
        return reg
    }

    public static func scaleFromRegistry(for asset: String) -> Int {
        if let reg = registry {
            return (try? Task<Int, Error>.runBlocking(operation: {
                await reg.getScale(for: asset)
            })) ?? AssetScale.scale(for: asset)
        }
        return AssetScale.scale(for: asset)
    }
}
