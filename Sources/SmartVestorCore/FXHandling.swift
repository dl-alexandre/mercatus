import Foundation

public struct FXSnapshot {
    public let id: UUID
    public let timestamp: Date
    public let rates: [String: Double]
    public let baseAsset: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rates: [String: Double],
        baseAsset: String = "USDC"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rates = rates
        self.baseAsset = baseAsset
    }

    public func normalize(_ amount: Double, from asset: String) -> Double {
        guard let rate = rates[asset.uppercased()] else {
            return amount
        }
        return amount * rate
    }
}

public class FXManager {
    private var currentSnapshot: FXSnapshot?

    public init() {}

    public func updateSnapshot(_ snapshot: FXSnapshot) {
        currentSnapshot = snapshot
    }

    public func getCurrentSnapshot() -> FXSnapshot? {
        return currentSnapshot
    }

    public func normalizeAmount(_ amount: Double, from asset: String, to baseAsset: String = "USDC") -> Double {
        guard let snapshot = currentSnapshot else {
            return amount
        }

        if asset.uppercased() == baseAsset.uppercased() {
            return amount
        }

        return snapshot.normalize(amount, from: asset)
    }
}
