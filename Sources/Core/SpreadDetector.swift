import Foundation
import Utils

/// Detects cross-exchange spreads from normalized price updates.
public actor SpreadDetector {
    private typealias ExchangeQuotes = [String: NormalizedPriceData]

    private let config: ArbitrageConfig
    private let logger: StructuredLogger?
    private var latestQuotes: [String: ExchangeQuotes] = [:]
    private var listeners: [UUID: AsyncStream<SpreadAnalysis>.Continuation] = [:]
    private let componentName = "SpreadDetector"

    public init(config: ArbitrageConfig, logger: StructuredLogger? = nil) {
        self.config = config
        self.logger = logger
    }

    /// Registers a consumer for spread analysis results.
    public func analysisStream() -> AsyncStream<SpreadAnalysis> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeListener(id: id) }
            }
        }
    }

    /// Consumes a normalized quote and evaluates potential spreads.
    public func ingest(_ quote: NormalizedPriceData) {
        var quotesForSymbol = latestQuotes[quote.symbol] ?? [:]
        quotesForSymbol[quote.exchange] = quote
        latestQuotes[quote.symbol] = quotesForSymbol

        guard quotesForSymbol.count >= 2 else { return }
        guard let bestBuy = quotesForSymbol.min(by: { $0.value.ask < $1.value.ask })?.value,
              let bestSell = quotesForSymbol.max(by: { $0.value.bid < $1.value.bid })?.value,
              bestBuy.exchange != bestSell.exchange else {
            return
        }

        let buyPrice = bestBuy.ask
        let sellPrice = bestSell.bid
        guard buyPrice > 0 else { return }

        let spreadPercentage = (sellPrice - buyPrice) / buyPrice
        let latencyMilliseconds = abs(bestSell.normalizedTime - bestBuy.normalizedTime) * 1000.0
        let spreadAsDouble = NSDecimalNumber(decimal: spreadPercentage).doubleValue

        let isProfitable = spreadAsDouble >= config.thresholds.minimumSpreadPercentage
            && latencyMilliseconds <= config.thresholds.maximumLatencyMilliseconds

        let analysis = SpreadAnalysis(
            symbol: quote.symbol,
            buyExchange: bestBuy.exchange,
            sellExchange: bestSell.exchange,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            spreadPercentage: spreadPercentage,
            latencyMilliseconds: latencyMilliseconds,
            isProfitable: isProfitable
        )

        logDetection(analysis)
        broadcast(analysis)
    }

    private func broadcast(_ analysis: SpreadAnalysis) {
        var terminated: [UUID] = []
        for (id, continuation) in listeners {
            let result = continuation.yield(analysis)
            if case .terminated = result {
                terminated.append(id)
            }
        }

        if !terminated.isEmpty {
            for id in terminated {
                listeners[id] = nil
            }
        }
    }

    private func logDetection(_ analysis: SpreadAnalysis) {
        logger?.info(
            component: componentName,
            event: "spread_calculated",
            data: [
                "symbol": analysis.symbol,
                "buy_exchange": analysis.buyExchange,
                "sell_exchange": analysis.sellExchange,
                "buy_price": decimalString(analysis.buyPrice),
                "sell_price": decimalString(analysis.sellPrice),
                "spread_percentage": decimalString(analysis.spreadPercentage),
                "latency_ms": string(from: analysis.latencyMilliseconds),
                "profitable": analysis.isProfitable ? "true" : "false"
            ]
        )
    }

    private func removeListener(id: UUID) {
        listeners[id] = nil
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func string(from value: Double) -> String {
        String(format: "%.3f", value)
    }
}
