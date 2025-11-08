import Foundation
import Utils

/// Detects triangular arbitrage opportunities within a single exchange.
public actor TriangularArbitrageDetector {

    public struct TriangularOpportunity: Sendable, Equatable {
        public let exchange: String
        public let path: [String]  // e.g., ["BTC", "ETH", "USD", "BTC"]
        public let startAmount: Decimal
        public let endAmount: Decimal
        public let profit: Decimal
        public let profitPercentage: Decimal
        public let isProfitable: Bool
        public let timestamp: Date

        public init(
            exchange: String,
            path: [String],
            startAmount: Decimal,
            endAmount: Decimal,
            profit: Decimal,
            profitPercentage: Decimal,
            isProfitable: Bool,
            timestamp: Date = Date()
        ) {
            self.exchange = exchange
            self.path = path
            self.startAmount = startAmount
            self.endAmount = endAmount
            self.profit = profit
            self.profitPercentage = profitPercentage
            self.isProfitable = isProfitable
            self.timestamp = timestamp
        }
    }

    private let config: ArbitrageConfig
    private let logger: StructuredLogger?
    private let componentName = "TriangularArbitrageDetector"

    // Store latest quotes by exchange and symbol
    private var exchangeQuotes: [String: [String: NormalizedPriceData]] = [:]
    private var listeners: [UUID: AsyncStream<TriangularOpportunity>.Continuation] = [:]

    // Comprehensive triangular paths to check (using BTC and ETH as base currencies)
    private let triangularPaths: [[String]] = [
        // BTC-based triangular arbitrage
        ["BTC", "ETH", "USD", "BTC"],
        ["BTC", "SOL", "USD", "BTC"],
        ["BTC", "LINK", "USD", "BTC"],
        ["BTC", "ADA", "USD", "BTC"],
        ["BTC", "DOT", "USD", "BTC"],
        ["BTC", "UNI", "USD", "BTC"],
        ["BTC", "AAVE", "USD", "BTC"],
        ["BTC", "LTC", "USD", "BTC"],
        ["BTC", "DOGE", "USD", "BTC"],
        ["BTC", "XRP", "USD", "BTC"],
        ["BTC", "MATIC", "USD", "BTC"],
        ["BTC", "AVAX", "USD", "BTC"],
        ["BTC", "ATOM", "USD", "BTC"],
        ["BTC", "NEAR", "USD", "BTC"],
        ["BTC", "FTM", "USD", "BTC"],
        ["BTC", "ALGO", "USD", "BTC"],
        ["BTC", "MANA", "USD", "BTC"],
        ["BTC", "SAND", "USD", "BTC"],
        ["BTC", "COMP", "USD", "BTC"],
        ["BTC", "CRV", "USD", "BTC"],
        ["BTC", "1INCH", "USD", "BTC"],
        ["BTC", "GRT", "USD", "BTC"],
        ["BTC", "FIL", "USD", "BTC"],
        ["BTC", "EGLD", "USD", "BTC"],
        ["BTC", "SNX", "USD", "BTC"],
        ["BTC", "ENS", "USD", "BTC"],
        ["BTC", "RUNE", "USD", "BTC"],
        ["BTC", "MKR", "USD", "BTC"],
        ["BTC", "ARPA", "USD", "BTC"],
        ["BTC", "OP", "USD", "BTC"],
        ["BTC", "LDO", "USD", "BTC"],
        ["BTC", "APE", "USD", "BTC"],
        ["BTC", "SUSHI", "USD", "BTC"],
        ["BTC", "BAL", "USD", "BTC"],
        ["BTC", "YFI", "USD", "BTC"],
        ["BTC", "GMT", "USD", "BTC"],
        ["BTC", "GALA", "USD", "BTC"],
        ["BTC", "IMX", "USD", "BTC"],
        ["BTC", "OCEAN", "USD", "BTC"],
        ["BTC", "STX", "USD", "BTC"],
        ["BTC", "HBAR", "USD", "BTC"],
        ["BTC", "ICP", "USD", "BTC"],
        ["BTC", "AXS", "USD", "BTC"],
        ["BTC", "CHZ", "USD", "BTC"],
        ["BTC", "CVC", "USD", "BTC"],
        ["BTC", "DASH", "USD", "BTC"],
        ["BTC", "ZRX", "USD", "BTC"],
        ["BTC", "KAVA", "USD", "BTC"],
        ["BTC", "RNDR", "USD", "BTC"],
        ["BTC", "FET", "USD", "BTC"],
        ["BTC", "AGIX", "USD", "BTC"],

        // ETH-based triangular arbitrage
        ["ETH", "BTC", "USD", "ETH"],
        ["ETH", "SOL", "USD", "ETH"],
        ["ETH", "LINK", "USD", "ETH"],
        ["ETH", "ADA", "USD", "ETH"],
        ["ETH", "DOT", "USD", "ETH"],
        ["ETH", "UNI", "USD", "ETH"],
        ["ETH", "AAVE", "USD", "ETH"],
        ["ETH", "LTC", "USD", "ETH"],
        ["ETH", "DOGE", "USD", "ETH"],
        ["ETH", "XRP", "USD", "ETH"],
        ["ETH", "MATIC", "USD", "ETH"],
        ["ETH", "AVAX", "USD", "ETH"],
        ["ETH", "ATOM", "USD", "ETH"],
        ["ETH", "NEAR", "USD", "ETH"],
        ["ETH", "FTM", "USD", "ETH"],
        ["ETH", "ALGO", "USD", "ETH"],
        ["ETH", "MANA", "USD", "ETH"],
        ["ETH", "SAND", "USD", "ETH"],
        ["ETH", "COMP", "USD", "ETH"],
        ["ETH", "CRV", "USD", "ETH"],
        ["ETH", "1INCH", "USD", "ETH"],
        ["ETH", "GRT", "USD", "ETH"],
        ["ETH", "FIL", "USD", "ETH"],
        ["ETH", "EGLD", "USD", "ETH"],
        ["ETH", "SNX", "USD", "ETH"],
        ["ETH", "ENS", "USD", "ETH"],
        ["ETH", "RUNE", "USD", "ETH"],
        ["ETH", "MKR", "USD", "ETH"],
        ["ETH", "ARPA", "USD", "ETH"],
        ["ETH", "OP", "USD", "ETH"],
        ["ETH", "LDO", "USD", "ETH"],
        ["ETH", "APE", "USD", "ETH"],
        ["ETH", "SUSHI", "USD", "ETH"],
        ["ETH", "BAL", "USD", "ETH"],
        ["ETH", "YFI", "USD", "ETH"],
        ["ETH", "GMT", "USD", "ETH"],
        ["ETH", "GALA", "USD", "ETH"],
        ["ETH", "IMX", "USD", "ETH"],
        ["ETH", "OCEAN", "USD", "ETH"],
        ["ETH", "STX", "USD", "ETH"],
        ["ETH", "HBAR", "USD", "ETH"],
        ["ETH", "ICP", "USD", "ETH"],
        ["ETH", "AXS", "USD", "ETH"],
        ["ETH", "CHZ", "USD", "ETH"],
        ["ETH", "CVC", "USD", "ETH"],
        ["ETH", "DASH", "USD", "ETH"],
        ["ETH", "ZRX", "USD", "ETH"],
        ["ETH", "KAVA", "USD", "ETH"],
        ["ETH", "RNDR", "USD", "ETH"],
        ["ETH", "FET", "USD", "ETH"],
        ["ETH", "AGIX", "USD", "ETH"]
    ]

    public init(config: ArbitrageConfig, logger: StructuredLogger? = nil) {
        self.config = config
        self.logger = logger
    }

    /// Starts periodic monitoring of all exchanges in parallel
    public func startPeriodicMonitoring(interval: TimeInterval = 1.0) async {
        while true {
            await checkAllExchangesInParallel()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func checkAllExchangesInParallel() async {
        await withTaskGroup(of: Void.self) { group in
            for exchange in exchangeQuotes.keys {
                group.addTask {
                    await self.checkTriangularOpportunities(for: exchange)
                }
            }
        }
    }

    /// Registers a consumer for triangular arbitrage opportunities.
    public func opportunityStream() -> AsyncStream<TriangularOpportunity> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeListener(id: id) }
            }
        }
    }

    /// Consumes a normalized quote and evaluates triangular arbitrage opportunities.
    public func ingest(_ quote: NormalizedPriceData) async {
        // Store quote by exchange and symbol
        if exchangeQuotes[quote.exchange] == nil {
            exchangeQuotes[quote.exchange] = [:]
        }
        exchangeQuotes[quote.exchange]![quote.symbol] = quote

        // Debug: Log what pairs we're receiving (only for cross-pairs to reduce noise)
        if quote.symbol.contains("-") && !quote.symbol.contains("-USD") {
            logger?.debug(
                component: componentName,
                event: "cross_pair_received",
                data: [
                    "exchange": quote.exchange,
                    "symbol": quote.symbol,
                    "bid": decimalString(quote.bid),
                    "ask": decimalString(quote.ask)
                ]
            )
        }

        // Check for triangular opportunities on this exchange in parallel
        Task { [exchange = quote.exchange] in
            await checkTriangularOpportunities(for: exchange)
        }
    }

    private func checkTriangularOpportunities(for exchange: String) async {
        guard let quotes = exchangeQuotes[exchange] else { return }

        // Debug: Log available pairs for this exchange
        let availablePairs = Array(quotes.keys).sorted()
        logger?.debug(
            component: componentName,
            event: "checking_triangular_opportunities",
            data: [
                "exchange": exchange,
                "available_pairs": availablePairs.joined(separator: ","),
                "pair_count": "\(availablePairs.count)"
            ]
        )

        // Process triangular paths in parallel using TaskGroup
        await withTaskGroup(of: TriangularOpportunity?.self) { group in
            for path in triangularPaths {
                group.addTask {
                    await self.checkSingleTriangularPath(
                        exchange: exchange,
                        path: path,
                        quotes: quotes
                    )
                }
            }

            // Collect results and broadcast profitable opportunities
            for await opportunity in group {
                guard !Task.isCancelled else { break }
                if let opportunity = opportunity, opportunity.isProfitable {
                    await self.logOpportunity(opportunity)
                    await self.broadcast(opportunity)
                }
            }
        }
    }

    private func checkSingleTriangularPath(
        exchange: String,
        path: [String],
        quotes: [String: NormalizedPriceData]
    ) async -> TriangularOpportunity? {
        guard path.count == 4 else { return nil } // Must be 3-step triangular path

        let startSymbol = path[0]
        let intermediate1 = path[1]
        let _ = path[2] // Not used in current logic
        let _ = path[0] // Not used in current logic

        // Check if we have all required quotes for triangular arbitrage
        // For path ["BTC", "ETH", "USD", "BTC"] we need:
        // 1. BTC-USD (to start with USD)
        // 2. BTC-ETH (to convert BTC to ETH)
        // 3. ETH-USD (to convert ETH back to USD)
        guard let startUSDQuote = quotes["\(startSymbol)-USD"],
              let intermediateUSDQuote = quotes["\(intermediate1)-USD"] else {
            return nil
        }

        // Try both directions for cross-pair
        let crossQuote: NormalizedPriceData
        if let directQuote = quotes["\(startSymbol)-\(intermediate1)"] {
            crossQuote = directQuote
        } else if let inverseQuote = quotes["\(intermediate1)-\(startSymbol)"] {
            // Calculate inverse rates
            crossQuote = NormalizedPriceData(
                exchange: inverseQuote.exchange,
                symbol: "\(startSymbol)-\(intermediate1)",
                bid: Decimal(1) / inverseQuote.ask, // Inverse of ask becomes bid
                ask: Decimal(1) / inverseQuote.bid, // Inverse of bid becomes ask
                rawTimestamp: inverseQuote.rawTimestamp,
                normalizedTime: inverseQuote.normalizedTime
            )
        } else {
            return nil
        }

        // Calculate triangular arbitrage
        return calculateTriangularArbitrage(
            exchange: exchange,
            path: path,
            quotes: [
                "\(startSymbol)-USD": startUSDQuote,
                "\(startSymbol)-\(intermediate1)": crossQuote,
                "\(intermediate1)-USD": intermediateUSDQuote
            ]
        )
    }

    private func calculateTriangularArbitrage(
        exchange: String,
        path: [String],
        quotes: [String: NormalizedPriceData]
    ) -> TriangularOpportunity {
        let startAmount = Decimal(1000) // Start with $1000 USD
        let feeRate = Decimal(0.001) // 0.1% per trade

        let startSymbol = path[0]
        let intermediate1 = path[1]

        // Get the required quotes
        let startUSDQuote = quotes["\(startSymbol)-USD"]!
        let crossQuote = quotes["\(startSymbol)-\(intermediate1)"]!
        let intermediateUSDQuote = quotes["\(intermediate1)-USD"]!

        // For BTC→ETH→USD→BTC path:
        // 1. Start with $1000 USD
        // 2. Buy BTC with USD (using BTC-USD ask price)
        // 3. Sell BTC for ETH (using BTC-ETH bid price)
        // 4. Sell ETH for USD (using ETH-USD bid price)

        // Step 1: USD → BTC (buy BTC with USD)
        let step1Amount = startAmount / startUSDQuote.ask // Buy BTC at ask
        let step1Fee = step1Amount * feeRate
        let step1Net = step1Amount - step1Fee

        // Step 2: BTC → ETH (sell BTC for ETH)
        let step2Amount = step1Net * crossQuote.bid // Sell BTC at bid (BTC-ETH)
        let step2Fee = step2Amount * feeRate
        let step2Net = step2Amount - step2Fee

        // Step 3: ETH → USD (sell ETH for USD)
        let step3Amount = step2Net * intermediateUSDQuote.bid // Sell ETH at bid
        let step3Fee = step3Amount * feeRate
        let finalAmount = step3Amount - step3Fee

        let profit = finalAmount - startAmount
        let profitPercentage = (profit / startAmount) * 100

        let minSpreadDecimal = Decimal(config.thresholds.minimumSpreadPercentage) * 100
        let isProfitable = profit > 0 && profitPercentage >= minSpreadDecimal

        return TriangularOpportunity(
            exchange: exchange,
            path: path,
            startAmount: startAmount,
            endAmount: finalAmount,
            profit: profit,
            profitPercentage: profitPercentage,
            isProfitable: isProfitable
        )
    }

    private func broadcast(_ opportunity: TriangularOpportunity) async {
        var terminated: [UUID] = []
        for (id, continuation) in listeners {
            guard !Task.isCancelled else { break }
            let result = continuation.yield(opportunity)
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

    private func logOpportunity(_ opportunity: TriangularOpportunity) async {
        logger?.info(
            component: componentName,
            event: "triangular_opportunity",
            data: [
                "exchange": opportunity.exchange,
                "path": opportunity.path.joined(separator: "→"),
                "start_amount": decimalString(opportunity.startAmount),
                "end_amount": decimalString(opportunity.endAmount),
                "profit": decimalString(opportunity.profit),
                "profit_percentage": decimalString(opportunity.profitPercentage),
                "profitable": opportunity.isProfitable ? "true" : "false"
            ]
        )
    }

    private func removeListener(id: UUID) {
        listeners[id] = nil
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
