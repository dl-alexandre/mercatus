import Foundation
import Utils

public typealias RawPriceData = Utils.RawPriceData

public extension RawPriceData {
    /// Basic sanity checks before attempting normalization.
    var isValidQuote: Bool {
        guard !exchange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard bid > 0, ask > 0 else { return false }
        return ask >= bid
    }
}

/// Price data with normalized precision and monotonic timestamp.
public struct NormalizedPriceData: Sendable, Equatable {
    public let exchange: String
    public let symbol: String
    public let bid: Decimal
    public let ask: Decimal
    public let rawTimestamp: Date
    public let normalizedTime: TimeInterval

    public init(
        exchange: String,
        symbol: String,
        bid: Decimal,
        ask: Decimal,
        rawTimestamp: Date,
        normalizedTime: TimeInterval
    ) {
        self.exchange = exchange
        self.symbol = symbol
        self.bid = bid
        self.ask = ask
        self.rawTimestamp = rawTimestamp
        self.normalizedTime = normalizedTime
    }

    /// Mid-price calculated from the normalized bid/ask quotes.
    public var mid: Decimal {
        (bid + ask) / Decimal(2)
    }
}

/// Result of comparing normalized quotes across venues.
public struct SpreadAnalysis: Sendable, Equatable {
    public let symbol: String
    public let buyExchange: String
    public let sellExchange: String
    public let buyPrice: Decimal
    public let sellPrice: Decimal
    public let spreadPercentage: Decimal
    public let latencyMilliseconds: Double
    public let isProfitable: Bool

    public init(
        symbol: String,
        buyExchange: String,
        sellExchange: String,
        buyPrice: Decimal,
        sellPrice: Decimal,
        spreadPercentage: Decimal,
        latencyMilliseconds: Double,
        isProfitable: Bool
    ) {
        self.symbol = symbol
        self.buyExchange = buyExchange
        self.sellExchange = sellExchange
        self.buyPrice = buyPrice
        self.sellPrice = sellPrice
        self.spreadPercentage = spreadPercentage
        self.latencyMilliseconds = latencyMilliseconds
        self.isProfitable = isProfitable
    }
}

/// Normalizes raw exchange quotes to a common precision and monotonic time domain.
public actor ExchangeNormalizer {
    public struct Configuration: Sendable, Equatable {
        public let staleInterval: TimeInterval
        public let minimumGap: TimeInterval

        public init(
            staleInterval: TimeInterval = 5.0,
            minimumGap: TimeInterval = 0.000_001
        ) {
            precondition(staleInterval > 0, "staleInterval must be > 0")
            precondition(minimumGap > 0, "minimumGap must be > 0")
            self.staleInterval = staleInterval
            self.minimumGap = minimumGap
        }
    }

    private let config: Configuration
    private let monotonicNow: @Sendable () -> TimeInterval
    private let wallClockNow: @Sendable () -> Date
    private let roundingScale: Int
    private var lastNormalizedTime: [String: TimeInterval] = [:]

    public init(
        config: Configuration = Configuration(),
        clock: ContinuousClock = ContinuousClock(),
        now: @escaping @Sendable () -> Date = Date.init,
        roundingScale: Int = 8,
        monotonicNow customMonotonicNow: (@Sendable () -> TimeInterval)? = nil
    ) {
        self.config = config
        self.wallClockNow = now
        self.roundingScale = roundingScale
        if let customMonotonicNow {
            self.monotonicNow = customMonotonicNow
        } else {
            let initialInstant = clock.now
            self.monotonicNow = {
                let instant = clock.now
                let duration = initialInstant.duration(to: instant)
                return duration.timeInterval
            }
        }
    }

    /// Attempts to normalize the provided raw quote. Returns `nil` when the quote is invalid or stale.
    public func normalize(_ data: RawPriceData) -> NormalizedPriceData? {
        guard data.isValidQuote else { return nil }

        let currentDate = wallClockNow()
        let age = currentDate.timeIntervalSince(data.timestamp)

        guard age >= 0 else { return nil }
        guard age <= config.staleInterval else { return nil }

        let roundedBid = data.bid.rounded(scale: roundingScale)
        let roundedAsk = data.ask.rounded(scale: roundingScale)

        guard roundedAsk >= roundedBid else { return nil }

        let key = keyFor(data)
        var monotonicTime = monotonicNow()

        if let last = lastNormalizedTime[key] {
            let delta = monotonicTime - last
            if delta < config.minimumGap {
                monotonicTime = last + config.minimumGap
            }
        }

        lastNormalizedTime[key] = monotonicTime

        return NormalizedPriceData(
            exchange: data.exchange,
            symbol: data.symbol,
            bid: roundedBid,
            ask: roundedAsk,
            rawTimestamp: data.timestamp,
            normalizedTime: monotonicTime
        )
    }

    private func keyFor(_ data: RawPriceData) -> String {
        "\(data.exchange.lowercased())|\(data.symbol.uppercased())"
    }

}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        let seconds = Double(parts.seconds)
        let attoseconds = Double(parts.attoseconds) / 1_000_000_000_000_000_000.0
        return seconds + attoseconds
    }
}
