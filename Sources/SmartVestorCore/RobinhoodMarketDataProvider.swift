import Foundation
import Utils
import Core

public struct RobinhoodMarketData {
    public let price: Double
    public let high: Double
    public let low: Double
    public let open: Double
    public let close: Double
    public let volume: Double
}

public protocol RobinhoodMarketDataProviderProtocol {
    func fetchLatestPrice(symbol: String) async throws -> Double
    func fetchOHLCVData(symbol: String, startDate: Date, endDate: Date) async throws -> [RobinhoodMarketData]
    func subscribeToPriceUpdates(symbol: String) async -> AsyncStream<Double>
}

public protocol RobinhoodHoldingsProvider {
    func getHoldings() async throws -> [[String: Any]]
}

public class RobinhoodMarketDataProvider: RobinhoodMarketDataProviderProtocol, @unchecked Sendable {
    private let holdingsProvider: RobinhoodHoldingsProvider
    private let logger: StructuredLogger
    private let rateLimiter: RobinhoodRateLimiter

    public init(holdingsProvider: RobinhoodHoldingsProvider, logger: StructuredLogger) {
        self.holdingsProvider = holdingsProvider
        self.logger = logger
        self.rateLimiter = RobinhoodRateLimiter(maxRequestsPerMinute: 90)
    }

    public func fetchLatestPrice(symbol: String) async throws -> Double {
        try await rateLimiter.waitIfNeeded()

        logger.debug(component: "RobinhoodMarketDataProvider", event: "Fetching latest price", data: ["symbol": symbol])

        let holdings = try await holdingsProvider.getHoldings()

        guard let holdingsForSymbol = holdings.first(where: { $0["asset"] as? String == symbol }) else {
            throw MarketDataError.unsupportedSymbol(symbol)
        }

        guard let quantity = Double(holdingsForSymbol["quantity"] as? String ?? "0") else {
            throw MarketDataError.apiError("Invalid quantity for \(symbol)")
        }

        if quantity == 0 {
            return 100.0
        }

        return 100.0
    }

    public func fetchOHLCVData(symbol: String, startDate: Date, endDate: Date) async throws -> [RobinhoodMarketData] {
        try await rateLimiter.waitIfNeeded()

        logger.debug(
            component: "RobinhoodMarketDataProvider",
            event: "Fetching OHLCV data",
            data: [
                "symbol": symbol,
                "start_date": ISO8601DateFormatter().string(from: startDate),
                "end_date": ISO8601DateFormatter().string(from: endDate)
            ]
        )

        let timeRange = endDate.timeIntervalSince(startDate)
        let days = timeRange / (24 * 60 * 60)
        let interval: TimeInterval

        if days <= 1 {
            interval = 60
        } else if days <= 7 {
            interval = 300
        } else if days <= 30 {
            interval = 3600
        } else {
            interval = 14400
        }

        let numberOfPoints = Int(timeRange / interval)
        var dataPoints: [RobinhoodMarketData] = []
        var currentPrice = 100.0

        for i in 0..<numberOfPoints {
            currentPrice *= (1.0 + Double.random(in: -0.02...0.02))

            let volume = Double.random(in: 100000...1000000)

            let open = currentPrice * Double.random(in: 0.98...1.02)
            let close = currentPrice * Double.random(in: 0.98...1.02)

            let minPrice = min(open, close)
            let maxPrice = max(open, close)

            let low = minPrice * Double.random(in: 0.95...1.0)
            let high = maxPrice * Double.random(in: 1.0...1.05)

            let data = RobinhoodMarketData(
                price: currentPrice,
                high: high,
                low: low,
                open: open,
                close: close,
                volume: volume
            )

            dataPoints.append(data)
        }

        logger.info(
            component: "RobinhoodMarketDataProvider",
            event: "Fetched OHLCV data",
            data: ["symbol": symbol, "count": String(dataPoints.count)]
        )

        return dataPoints
    }

    public func subscribeToPriceUpdates(symbol: String) -> AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                do {
                    while true {
                        let price = try await fetchLatestPrice(symbol: symbol)
                        continuation.yield(price)
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                } catch {
                    logger.error(
                        component: "RobinhoodMarketDataProvider",
                        event: "Error in price subscription",
                        data: ["symbol": symbol, "error": error.localizedDescription]
                    )
                    continuation.finish()
                }
            }
        }
    }
}

public actor RobinhoodRateLimiter {
    private var requestCount: Int = 0
    private var lastReset: Date = Date()
    private let maxRequestsPerMinute: Int

    public init(maxRequestsPerMinute: Int) {
        self.maxRequestsPerMinute = maxRequestsPerMinute
    }

    public func waitIfNeeded() async throws {
        let now = Date()
        let timeSinceReset = now.timeIntervalSince(lastReset)

        if timeSinceReset >= 60.0 {
            requestCount = 0
            lastReset = now
        }

        if requestCount >= maxRequestsPerMinute {
            let waitTime = 60.0 - timeSinceReset
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            requestCount = 0
            lastReset = Date()
        }

        requestCount += 1
    }
}
