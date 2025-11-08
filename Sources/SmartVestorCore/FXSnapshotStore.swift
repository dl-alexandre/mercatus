import Foundation

public struct FXSnapshotRecord {
    public let id: UUID
    public let provider: String
    public let timestamp: Date
    public let rates: [String: Double]
    public let baseAsset: String
    public let pairs: [String]

    public init(
        id: UUID = UUID(),
        provider: String,
        timestamp: Date,
        rates: [String: Double],
        baseAsset: String = "USDC",
        pairs: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.timestamp = timestamp
        self.rates = rates
        self.baseAsset = baseAsset
        self.pairs = pairs.isEmpty ? Array(rates.keys) : pairs
    }

    public func isStale(maxAgeMinutes: Int = 5) -> Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age > Double(maxAgeMinutes * 60)
    }

    public func normalize(_ amount: Double, from asset: String) -> Double {
        guard let rate = rates[asset.uppercased()] else {
            return amount
        }
        return amount * rate
    }
}

public actor FXSnapshotStore {
    private var snapshots: [UUID: FXSnapshotRecord] = [:]
    private var currentSnapshotID: UUID?
    private let maxStaleMinutes: Int

    public init(maxStaleMinutes: Int = 5) {
        self.maxStaleMinutes = maxStaleMinutes
    }

    public func store(_ snapshot: FXSnapshotRecord) {
        snapshots[snapshot.id] = snapshot
        currentSnapshotID = snapshot.id
    }

    public func getCurrent() -> FXSnapshotRecord? {
        guard let id = currentSnapshotID,
              let snapshot = snapshots[id] else {
            return nil
        }
        return snapshot
    }

    public func validateForCrossAssetPL() throws {
        guard let snapshot = getCurrent() else {
            throw SmartVestorError.validationError("No FX snapshot available")
        }

        guard !snapshot.isStale(maxAgeMinutes: maxStaleMinutes) else {
            throw SmartVestorError.validationError("FX snapshot is stale: \(snapshot.timestamp)")
        }
    }
}
