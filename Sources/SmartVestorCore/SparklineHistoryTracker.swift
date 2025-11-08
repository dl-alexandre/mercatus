import Foundation

public final class SparklineHistoryTracker: @unchecked Sendable {
    private let config: SparklineConfig
    private let historyLock = NSLock()
    private var _portfolioHistory: [Double] = []
    private var _assetPriceHistory: [String: [Double]] = [:]
    private var _timestamps: [Date] = []

    public init(config: SparklineConfig = .default) {
        self.config = config
    }

    public func updatePortfolioValue(_ value: Double, timestamp: Date = Date()) {
        guard config.enabled && config.showPortfolioHistory else {
            return
        }

        historyLock.lock()
        defer { historyLock.unlock() }

        _portfolioHistory.append(value)
        _timestamps.append(timestamp)

        if _portfolioHistory.count > config.historyLength {
            _portfolioHistory.removeFirst()
            _timestamps.removeFirst()
        }
    }

    public func updateAssetPrice(_ asset: String, price: Double, timestamp: Date = Date()) {
        guard config.enabled && config.showAssetTrends else {
            return
        }

        historyLock.lock()
        defer { historyLock.unlock() }

        if _assetPriceHistory[asset] == nil {
            _assetPriceHistory[asset] = []
        }

        _assetPriceHistory[asset]?.append(price)

        if let count = _assetPriceHistory[asset]?.count, count > config.historyLength {
            _assetPriceHistory[asset]?.removeFirst()
        }
    }

    public func getPortfolioHistory() -> [Double] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return _portfolioHistory
    }

    public func getAssetHistory(_ asset: String) -> [Double] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return _assetPriceHistory[asset] ?? []
    }

    public func clear() {
        historyLock.lock()
        defer { historyLock.unlock() }
        _portfolioHistory.removeAll()
        _assetPriceHistory.removeAll()
        _timestamps.removeAll()
    }
}
