import Foundation

public struct AssetScale {
    public static let btc: Int = 8
    public static let eth: Int = 8
    public static let usdc: Int = 6
    public static let defaultScale: Int = 8

    public static func scale(for asset: String) -> Int {
        switch asset.uppercased() {
        case "BTC", "ETH":
            return 8
        case "USDC", "USDT":
            return 6
        default:
            return defaultScale
        }
    }

    public static func validateScale(_ amount: Double, asset: String) throws {
        let scale = scale(for: asset)
        let multiplier = pow(10.0, Double(scale))
        let scaled = amount * multiplier
        let rounded = round(scaled)

        if abs(scaled - rounded) > 1e-10 {
            throw SmartVestorError.validationError("Amount \(amount) exceeds precision for asset \(asset) (scale: \(scale))")
        }
    }

    public static func toFixedPoint(_ amount: Double, asset: String) -> UInt128 {
        let scale = scale(for: asset)
        let multiplier = pow(10.0, Double(scale))
        let scaled = round(amount * multiplier)
        return UInt128(UInt64(scaled))
    }

    public static func fromFixedPoint(_ fixed: UInt128, asset: String) -> Double {
        let scale = scale(for: asset)
        let multiplier = pow(10.0, Double(scale))
        return fixed.asDouble / multiplier
    }
}

extension TigerBeetlePersistence {
    func validateAmountPrecision(_ amount: Double, asset: String) throws {
        try AssetScale.validateScale(amount, asset: asset)
    }
}
