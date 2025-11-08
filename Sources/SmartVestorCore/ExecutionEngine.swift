import Foundation
import Utils
import Core

public protocol ExecutionEngineProtocol {
    func executePlan(_ plan: AllocationPlan, dryRun: Bool) async throws -> [ExecutionResult]
    func analyzeMarketConditions() async throws -> MarketCondition
    func placeMakerOrder(asset: String, quantity: Double, exchange: String, dryRun: Bool) async throws -> ExecutionResult
}

public class ExecutionEngine: ExecutionEngineProtocol {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]
    private let crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol?
    private let swapAnalyzer: SwapAnalyzerProtocol?
    private let logger: StructuredLogger
    private let backpressureThrottle: BackpressureThrottle?
    private let traceIDGenerator: () -> String

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        exchangeConnectors: [String: ExchangeConnectorProtocol] = [:],
        crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol? = nil,
        swapAnalyzer: SwapAnalyzerProtocol? = nil,
        backpressureThrottle: BackpressureThrottle? = nil,
        traceIDGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.config = config
        self.persistence = persistence
        self.exchangeConnectors = exchangeConnectors
        self.crossExchangeAnalyzer = crossExchangeAnalyzer
        self.swapAnalyzer = swapAnalyzer
        self.logger = StructuredLogger()
        self.backpressureThrottle = backpressureThrottle
        self.traceIDGenerator = traceIDGenerator
    }

    public func executePlan(_ plan: AllocationPlan, dryRun: Bool) async throws -> [ExecutionResult] {
        let envValue = ProcessInfo.processInfo.environment["EXECUTIONENGINE_WRITES"]
        if envValue == "false" {
            throw SmartVestorError.executionError("ExecutionEngine writes are frozen for cutover")
        }

        try await checkBackpressure(throttle: backpressureThrottle)

        logger.info(component: "ExecutionEngine", event: "Executing allocation plan", data: [
            "plan_id": plan.id.uuidString,
            "dry_run": String(dryRun)
        ])

        let marketCondition = try await analyzeMarketConditions()
        if marketCondition.shouldDelay {
            logger.warn(component: "ExecutionEngine", event: "Market conditions indicate delay", data: [
                "rsi": String(marketCondition.rsi),
                "price_vs_ma30": String(marketCondition.priceVsMA30)
            ])
            throw SmartVestorError.executionError("Market overheated - execution delayed")
        }

        var results: [ExecutionResult] = []

        if let _ = exchangeConnectors["robinhood"] {
            let robinhoodResults = try await executePlanOnRobinhood(plan: plan, dryRun: dryRun)
            results.append(contentsOf: robinhoodResults)
            return results
        }

        let accounts = try persistence.getAllAccounts()
        let usdcAccount = accounts.first { $0.asset == "USDC" }
        guard let usdcBalance = usdcAccount?.available, usdcBalance > 0 else {
            throw SmartVestorError.executionError("No USDC balance available for execution")
        }

        let totalAmount = usdcBalance
        let btcAmount = totalAmount * plan.adjustedAllocation.btc
        let ethAmount = totalAmount * plan.adjustedAllocation.eth

        if btcAmount > 0 {
            let result = try await placeMakerOrder(
                asset: "BTC",
                quantity: btcAmount,
                exchange: "kraken",
                dryRun: dryRun
            )
            results.append(result)
        }

        if ethAmount > 0 {
            let result = try await placeMakerOrder(
                asset: "ETH",
                quantity: ethAmount,
                exchange: "kraken",
                dryRun: dryRun
            )
            results.append(result)
        }

        for altcoin in plan.adjustedAllocation.altcoins {
            let altcoinAmount = totalAmount * altcoin.percentage
            let result = try await placeMakerOrder(
                asset: altcoin.symbol,
                quantity: altcoinAmount,
                exchange: altcoin.exchange,
                dryRun: dryRun
            )
            results.append(result)
        }

        logger.info(component: "ExecutionEngine", event: "Plan execution completed", data: [
            "plan_id": plan.id.uuidString,
            "total_orders": String(results.count),
            "successful_orders": String(results.filter { $0.success }.count)
        ])

        return results
    }

    private func executePlanOnRobinhood(plan: AllocationPlan, dryRun: Bool) async throws -> [ExecutionResult] {
        guard let rh = exchangeConnectors["robinhood"] else { return [] }

        let accounts = try persistence.getAllAccounts()
        let usdAccount = accounts.first { $0.exchange == "robinhood" && ($0.asset == "USD" || $0.asset == "USDC") }
        guard let buyingPower = usdAccount?.available, buyingPower > 0 else {
            throw SmartVestorError.executionError("No USD/USDC buying power available on Robinhood")
        }

        let provider = MultiProviderMarketDataProvider()

        var symbols: [String] = ["BTC", "ETH"] + plan.adjustedAllocation.altcoins.map { $0.symbol }
        symbols = Array(Set(symbols))
        let prices = (try? await provider.getCurrentPrices(symbols: symbols)) ?? [:]

        var results: [ExecutionResult] = []

        func priceFor(_ symbol: String) -> Double { prices[symbol] ?? 0 }

        var totalAmount = buyingPower
        let btcAmount = totalAmount * plan.adjustedAllocation.btc
        let ethAmount = totalAmount * plan.adjustedAllocation.eth

        let minNotionalUSD = 1.0
        let orderSpacingNs: UInt64 = 200_000_000
        let cancelAfterSeconds: Double = 15

        if btcAmount >= minNotionalUSD, priceFor("BTC") > 0 {
            let qty = roundQuantity(asset: "BTC", quantity: btcAmount / priceFor("BTC"))
            if qty * priceFor("BTC") >= minNotionalUSD {
                let res = try await placeRobinhoodMarketOrder(connector: rh, asset: "BTC", quantity: qty, side: .buy, dryRun: dryRun, cancelAfterSeconds: cancelAfterSeconds)
                results.append(res)
                totalAmount -= btcAmount
                try? await Task.sleep(nanoseconds: orderSpacingNs)
            }
        }

        if ethAmount >= minNotionalUSD, priceFor("ETH") > 0 {
            let qty = roundQuantity(asset: "ETH", quantity: ethAmount / priceFor("ETH"))
            if qty * priceFor("ETH") >= minNotionalUSD {
                let res = try await placeRobinhoodMarketOrder(connector: rh, asset: "ETH", quantity: qty, side: .buy, dryRun: dryRun, cancelAfterSeconds: cancelAfterSeconds)
                results.append(res)
                totalAmount -= ethAmount
                try? await Task.sleep(nanoseconds: orderSpacingNs)
            }
        }

        for alt in plan.adjustedAllocation.altcoins {
            let allocUsd = buyingPower * alt.percentage
            guard allocUsd >= minNotionalUSD, priceFor(alt.symbol) > 0 else { continue }
            let qty = roundQuantity(asset: alt.symbol, quantity: allocUsd / priceFor(alt.symbol))
            guard qty * priceFor(alt.symbol) >= minNotionalUSD else { continue }
            let res = try await placeRobinhoodMarketOrder(connector: rh, asset: alt.symbol, quantity: qty, side: .buy, dryRun: dryRun, cancelAfterSeconds: cancelAfterSeconds)
            results.append(res)
            try? await Task.sleep(nanoseconds: orderSpacingNs)
        }

        let holdings = try persistence.getAllAccounts().filter { $0.exchange == "robinhood" }

        if let analyzer = swapAnalyzer, let swapConfig = config.swapAnalysis, swapConfig.enabled {
            logger.info(component: "ExecutionEngine", event: "Evaluating swaps for rebalancing")

            let swapEvaluations = try await analyzer.findOptimalSwaps(
                currentHoldings: holdings,
                targetAllocation: plan.adjustedAllocation,
                exchanges: ["robinhood"]
            )

            for evaluation in swapEvaluations where analyzer.shouldExecuteSwap(evaluation) {
                logger.info(component: "ExecutionEngine", event: "Executing worthwhile swap", data: [
                    "fromAsset": evaluation.fromAsset,
                    "toAsset": evaluation.toAsset,
                    "netValue": String(evaluation.netValue),
                    "confidence": String(evaluation.confidence)
                ])

                let sellRes = try await placeRobinhoodMarketOrder(
                    connector: rh,
                    asset: evaluation.fromAsset,
                    quantity: evaluation.fromQuantity,
                    side: .sell,
                    dryRun: dryRun,
                    cancelAfterSeconds: cancelAfterSeconds
                )
                results.append(sellRes)

                if sellRes.success {
                    try? await Task.sleep(nanoseconds: orderSpacingNs)

                    let buyRes = try await placeRobinhoodMarketOrder(
                        connector: rh,
                        asset: evaluation.toAsset,
                        quantity: evaluation.estimatedToQuantity,
                        side: .buy,
                        dryRun: dryRun,
                        cancelAfterSeconds: cancelAfterSeconds
                    )
                    results.append(buyRes)
                    try? await Task.sleep(nanoseconds: orderSpacingNs)
                }
            }
        } else {
            let rebalanceThreshold = 0.10
            let targetWeights: [String: Double] = {
                var map: [String: Double] = [:]
                var total = plan.adjustedAllocation.btc + plan.adjustedAllocation.eth + plan.adjustedAllocation.altcoins.reduce(0) { $0 + $1.percentage }
                if total <= 0 { total = 1 }
                map["BTC"] = plan.adjustedAllocation.btc / total
                map["ETH"] = plan.adjustedAllocation.eth / total
                for a in plan.adjustedAllocation.altcoins { map[a.symbol] = a.percentage / total }
                return map
            }()
            let symbolsSet = Set(targetWeights.keys)
            let totalValue = holdings.reduce(0.0) { acc, h in acc + (prices[h.asset] ?? 0) * h.total }
            if totalValue > 0 {
                for h in holdings where symbolsSet.contains(h.asset) {
                    let price = prices[h.asset] ?? 0
                    if price <= 0 { continue }
                    let currentValue = h.total * price
                    let targetValue = totalValue * (targetWeights[h.asset] ?? 0)
                    if currentValue > targetValue * (1.0 + rebalanceThreshold) {
                        let excessUSD = currentValue - targetValue
                        let qtyToSell = roundQuantity(asset: h.asset, quantity: excessUSD / price)
                        if qtyToSell * price >= minNotionalUSD {
                            let res = try await placeRobinhoodMarketOrder(connector: rh, asset: h.asset, quantity: qtyToSell, side: .sell, dryRun: dryRun, cancelAfterSeconds: cancelAfterSeconds)
                            results.append(res)
                            try? await Task.sleep(nanoseconds: orderSpacingNs)
                        }
                    }
                }
            }
        }

        // Post-trade refresh of Robinhood balances
        _ = try await refreshRobinhoodBalances()

        return results
    }

    private func placeRobinhoodMarketOrder(connector: ExchangeConnectorProtocol, asset: String, quantity: Double, side: OrderSide, dryRun: Bool, cancelAfterSeconds: Double) async throws -> ExecutionResult {
        if dryRun {
            let mockPrice = generateMockPrice(for: asset)
            return ExecutionResult(asset: asset, quantity: quantity, price: mockPrice, exchange: "robinhood", success: true)
        }

        // Market order using Robinhood connector; symbol uses dash-USD per docs
        let symbol = "\(asset)-USD"
        do {
            let order = try await connector.placeOrder(
                symbol: symbol,
                side: side,
                type: OrderType.market,
                quantity: quantity,
                price: 0
            )

            await pollOrderFill(orderId: order.id, timeoutSeconds: cancelAfterSeconds)

            var tx = InvestmentTransaction(
                type: side == .buy ? .buy : .sell,
                exchange: "robinhood",
                asset: asset,
                quantity: quantity,
                price: 0,
                fee: 0,
                timestamp: Date(),
                metadata: [
                    "order_id": order.id,
                    "order_type": "market",
                    "side": side == .buy ? "buy" : "sell",
                    "source_event_id": order.id,
                    "source_system": "robinhood"
                ]
            )
            let traceID = traceIDGenerator()
            tx = tx.withTraceID(traceID)
            try persistence.saveTransaction(tx)

            return ExecutionResult(asset: asset, quantity: quantity, price: 0, exchange: "robinhood", success: true, orderId: order.id)
        } catch {
            return ExecutionResult(asset: asset, quantity: quantity, price: 0, exchange: "robinhood", success: false, error: error.localizedDescription)
        }
    }

    private func pollOrderFill(orderId: String, timeoutSeconds: Double) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
            break
        }
    }

    private func roundQuantity(asset: String, quantity: Double) -> Double {
        let step: Double = 0.000001
        return (quantity / step).rounded() * step
    }

    public func refreshRobinhoodBalances() async throws -> [Holding] {
        guard let robinhoodConnector = exchangeConnectors["robinhood"] else {
            logger.warn(component: "ExecutionEngine", event: "Robinhood connector not available for balance refresh")
            return []
        }

        logger.debug(component: "ExecutionEngine", event: "Connector type check", data: [
            "type": String(describing: type(of: robinhoodConnector)),
            "name": robinhoodConnector.name,
            "has_connect": "\(robinhoodConnector is ExchangeConnector)"
        ])

        // Use protocol method - RobinhoodConnector implements this
        let rawHoldings = try await robinhoodConnector.getHoldings()
        let existingAll = try persistence.getAllAccounts().filter { $0.exchange == "robinhood" }
        var existingMap: [String: Holding] = [:]
        for h in existingAll { existingMap[h.asset] = h }

        func parseDouble(_ value: Any?) -> Double? {
            if let str = value as? String {
                return Double(str)
            } else if let num = value as? Double {
                return Double(num)
            } else if let num = value as? Int {
                return Double(num)
            }
            return nil
        }

        var assetsToKeep = Set<String>()
        var refreshedBalances: [Holding] = []

        for item in rawHoldings {
            guard let asset = item["asset"] as? String ?? item["assetCode"] as? String else { continue }

            let totalQuantity = parseDouble(item["quantity"]) ?? 0.0
            let availableQuantity = parseDouble(item["available"]) ?? totalQuantity
            let pendingQuantity = parseDouble(item["pending"]) ?? 0.0
            let stakedQuantity = parseDouble(item["staked"]) ?? 0.0

            if totalQuantity > 0 || availableQuantity > 0 || pendingQuantity > 0 || stakedQuantity > 0 {
                assetsToKeep.insert(asset)

                let nonAvailable = totalQuantity - availableQuantity
                let pending = pendingQuantity > 0 ? pendingQuantity : (nonAvailable > 0 ? nonAvailable : 0.0)
                let staked = stakedQuantity > 0 ? stakedQuantity : 0.0

                let existing = existingMap[asset]
                let account = Holding(
                    id: existing?.id ?? UUID(),
                    exchange: "robinhood",
                    asset: asset,
                    available: availableQuantity,
                    pending: pending,
                    staked: staked,
                    updatedAt: Date()
                )
                try persistence.saveAccount(account)
                refreshedBalances.append(account)
            }
        }

        for (asset, existing) in existingMap {
            if !assetsToKeep.contains(asset) && asset != "USD" {
                let zeroAccount = Holding(
                    id: existing.id,
                    exchange: "robinhood",
                    asset: asset,
                    available: 0,
                    pending: 0,
                    staked: 0,
                    updatedAt: Date()
                )
                try persistence.saveAccount(zeroAccount)
            }
        }

        let accountInfo = try? await robinhoodConnector.getAccountBalance()
        if let accountInfo = accountInfo,
           let bpStr = accountInfo["crypto_buying_power"],
           let bp = Double(bpStr), bp >= 0 {
            let existingUSD = try? persistence.getAccount(exchange: "robinhood", asset: "USD")
            let usdHolding = Holding(
                id: existingUSD?.id ?? UUID(),
                exchange: "robinhood",
                asset: "USD",
                available: bp,
                pending: 0,
                staked: 0,
                updatedAt: Date()
            )
            try persistence.saveAccount(usdHolding)
            refreshedBalances.append(usdHolding)
        }

        logger.debug(component: "ExecutionEngine", event: "Balances refreshed", data: [
            "asset_count": String(refreshedBalances.count)
        ])

        return refreshedBalances
    }

    private func refreshRobinhoodBalances(connector: ExchangeConnectorProtocol) async throws {
        _ = try await refreshRobinhoodBalances()
    }

    private func refreshRobinhoodBalances_OLD(connector: ExchangeConnectorProtocol) async throws {
        do {
            guard connector.name.lowercased().contains("robinhood") else { return }
            let rawHoldings = try await connector.getHoldings()
            let db = self.persistence
            let existingAll = try db.getAllAccounts().filter { $0.exchange == "robinhood" }
            var existingMap: [String: Holding] = [:]
            for h in existingAll { existingMap[h.asset] = h }

            func parseDouble(_ value: Any?) -> Double? {
                if let str = value as? String {
                    return Double(str)
                } else if let num = value as? Double {
                    return num
                } else if let num = value as? Int {
                    return Double(num)
                }
                return nil
            }

            for item in rawHoldings {
                guard
                    let asset = item["asset"] as? String ?? item["assetCode"] as? String,
                    let available = parseDouble(item["available"]) ?? parseDouble(item["quantity"])
                else { continue }
                if available > 0 {
                    let existing = existingMap[asset]
                    let account = Holding(
                        id: existing?.id ?? UUID(),
                        exchange: "robinhood",
                        asset: asset,
                        available: available,
                        pending: parseDouble(item["pending"]) ?? 0,
                        staked: parseDouble(item["staked"]) ?? 0,
                        updatedAt: Date()
                    )
                    try db.saveAccount(account)
                }
            }
            let accountInfo = try await connector.getAccountBalance()
            if let bpStr = accountInfo["crypto_buying_power"], let bp = Double(bpStr), bp >= 0 {
                let existingUSD = try db.getAccount(exchange: "robinhood", asset: "USD")
                let usdHolding = Holding(
                    id: existingUSD?.id ?? UUID(),
                    exchange: "robinhood",
                    asset: "USD",
                    available: bp,
                    pending: 0,
                    staked: 0,
                    updatedAt: Date()
                )
                try db.saveAccount(usdHolding)
            }
        } catch {}
    }

    public func analyzeMarketConditions() async throws -> MarketCondition {
        logger.info(component: "ExecutionEngine", event: "Analyzing market conditions")

        let btcPrices = try await getRecentPrices(symbol: "BTC", period: 30)
        let ethPrices = try await getRecentPrices(symbol: "ETH", period: 30)

        let btcRSI = calculateRSI(prices: btcPrices)
        let ethRSI = calculateRSI(prices: ethPrices)
        let avgRSI = (btcRSI + ethRSI) / 2.0

        let btcMA30 = calculateMovingAverage(prices: btcPrices, period: 30)
        let ethMA30 = calculateMovingAverage(prices: ethPrices, period: 30)
        let currentBTCPrice = btcPrices.last ?? 0.0
        let currentETHPrice = ethPrices.last ?? 0.0

        let btcPriceVsMA = btcMA30 > 0 ? currentBTCPrice / btcMA30 : 1.0
        let ethPriceVsMA = ethMA30 > 0 ? currentETHPrice / ethMA30 : 1.0
        let avgPriceVsMA = (btcPriceVsMA + ethPriceVsMA) / 2.0

        let isOverheated = avgRSI >= config.rsiThreshold || avgPriceVsMA >= config.priceThreshold
        let shouldDelay = isOverheated

        let condition = MarketCondition(
            rsi: avgRSI,
            priceVsMA30: avgPriceVsMA,
            isOverheated: isOverheated,
            shouldDelay: shouldDelay
        )

        logger.info(component: "ExecutionEngine", event: "Market condition analysis completed", data: [
            "rsi": String(avgRSI),
            "price_vs_ma30": String(avgPriceVsMA),
            "is_overheated": String(isOverheated),
            "should_delay": String(shouldDelay)
        ])

        return condition
    }

    public func placeMakerOrder(asset: String, quantity: Double, exchange: String, dryRun: Bool) async throws -> ExecutionResult {
        logger.info(component: "ExecutionEngine", event: "Placing maker order", data: [
            "asset": asset,
            "quantity": String(quantity),
            "exchange": exchange,
            "dry_run": String(dryRun)
        ])

        if dryRun {
            let mockPrice = generateMockPrice(for: asset)
            let result = ExecutionResult(
                asset: asset,
                quantity: quantity,
                price: mockPrice,
                exchange: exchange,
                success: true
            )

            logger.info(component: "ExecutionEngine", event: "Mock order placed", data: [
                "asset": asset,
                "quantity": String(quantity),
                "price": String(mockPrice)
            ])

            return result
        }

        guard let connector = exchangeConnectors[exchange] else {
            let error = "No connector available for exchange: \(exchange)"
            logger.error(component: "ExecutionEngine", event: "Exchange connector not found", data: [
                "exchange": exchange,
                "error": error
            ])

            return ExecutionResult(
                asset: asset,
                quantity: quantity,
                price: 0.0,
                exchange: exchange,
                success: false,
                error: error
            )
        }

        do {
            var spreadAnalysis: SpreadAnalysis?
            if let analyzer = crossExchangeAnalyzer {
                do {
                    let analyses = try await analyzer.analyzeSpreads(for: [asset])
                    spreadAnalysis = analyses[asset]
                    if let analysis = spreadAnalysis {
                        logger.info(component: "ExecutionEngine", event: "Spread analysis completed", data: [
                            "asset": asset,
                            "spread_percentage": String(analysis.spreadPercentage),
                            "meets_fee_cap": String(analysis.meetsFeeCap),
                            "best_exchange": analysis.bestExchange
                        ])
                        if !analysis.meetsFeeCap {
                            logger.warn(component: "ExecutionEngine", event: "Spread exceeds fee cap threshold", data: [
                                "asset": asset,
                                "spread_percentage": String(analysis.spreadPercentage),
                                "fee_cap": String(config.feeCap * 100)
                            ])
                        }
                        if analysis.bestExchange != exchange && !analysis.bestExchange.isEmpty {
                            logger.info(component: "ExecutionEngine", event: "Switching to best exchange based on spread", data: [
                                "asset": asset,
                                "requested_exchange": exchange,
                                "best_exchange": analysis.bestExchange
                            ])
                        }
                    }
                } catch {
                    logger.warn(component: "ExecutionEngine", event: "Spread analysis failed, proceeding with order", data: [
                        "asset": asset,
                        "error": error.localizedDescription
                    ])
                }
            }

            let orderBook = try await connector.getOrderBook(symbol: "\(asset)USDC")
            let bestBid = orderBook.bids.first?.price ?? 0.0
            let bestAsk = orderBook.asks.first?.price ?? 0.0
            guard bestBid > 0 && bestAsk > 0 else {
                let error = "Invalid order book: missing bid/ask prices"
                logger.error(component: "ExecutionEngine", event: "Invalid order book", data: [
                    "asset": asset,
                    "exchange": exchange,
                    "best_bid": String(bestBid),
                    "best_ask": String(bestAsk)
                ])
                return ExecutionResult(
                    asset: asset,
                    quantity: quantity,
                    price: 0.0,
                    exchange: exchange,
                    success: false,
                    error: error
                )
            }

            let spread = bestAsk - bestBid
            let midPrice = (bestBid + bestAsk) / 2.0
            let spreadPercentage = (spread / midPrice) * 100.0
            logger.info(component: "ExecutionEngine", event: "Order book spread calculated", data: [
                "asset": asset,
                "exchange": exchange,
                "best_bid": String(bestBid),
                "best_ask": String(bestAsk),
                "spread_percentage": String(spreadPercentage)
            ])
            let maxSpreadPercentage = 2.0
            if spreadPercentage > maxSpreadPercentage {
                let error = "Spread too wide: \(String(format: "%.2f", spreadPercentage))% exceeds maximum \(maxSpreadPercentage)%"
                logger.warn(component: "ExecutionEngine", event: "Spread exceeds threshold, blocking order", data: [
                    "asset": asset,
                    "exchange": exchange,
                    "spread_percentage": String(spreadPercentage),
                    "max_spread": String(maxSpreadPercentage)
                ])
                return ExecutionResult(
                    asset: asset,
                    quantity: quantity,
                    price: 0.0,
                    exchange: exchange,
                    success: false,
                    error: error
                )
            }

            let makerPrice = bestBid + (bestAsk - bestBid) * 0.1

            // Retryable order placement
            let retry = RetryHandler(logger: logger)
            let order = try await retry.execute(maxAttempts: 3, initialDelay: 1.0, maxDelay: 30.0, multiplier: 2.0) {
                try await connector.placeOrder(
                    symbol: "\(asset)USDC",
                    side: OrderSide.buy,
                    type: OrderType.limit,
                    quantity: quantity,
                    price: makerPrice
                )
            }

            let notional = quantity * makerPrice
            let feeUsd = notional * 0.001
            var transaction = InvestmentTransaction(
                type: .buy,
                exchange: exchange,
                asset: asset,
                quantity: quantity,
                price: makerPrice,
                fee: feeUsd,
                timestamp: Date(),
                metadata: [
                    "order_id": order.id,
                    "order_type": "maker",
                    "notional_usd": String(format: "%.6f", notional),
                    "fee_usd": String(format: "%.6f", feeUsd),
                    "total_usd": String(format: "%.6f", notional + feeUsd),
                    "source_event_id": order.id,
                    "source_system": exchange
                ]
            )
            transaction = transaction.withTraceID(traceIDGenerator())
            try persistence.saveTransaction(transaction)

            let result = ExecutionResult(
                asset: asset,
                quantity: quantity,
                price: makerPrice,
                exchange: exchange,
                success: true
            )

            logger.info(component: "ExecutionEngine", event: "Order placed successfully", data: [
                "asset": asset,
                "quantity": String(quantity),
                "price": String(makerPrice),
                "order_id": order.id
            ])

            return result

        } catch {
            let errorMessage = error.localizedDescription
            logger.error(component: "ExecutionEngine", event: "Failed to place order", data: [
                "asset": asset,
                "exchange": exchange,
                "error": errorMessage
            ])

            return ExecutionResult(
                asset: asset,
                quantity: quantity,
                price: 0.0,
                exchange: exchange,
                success: false,
                error: errorMessage
            )
        }
    }

    private func getRecentPrices(symbol: String, period: Int) async throws -> [Double] {
        let mockPrices = generateMockPrices(symbol: symbol, count: period)
        return mockPrices
    }

    private func generateMockPrices(symbol: String, count: Int) -> [Double] {
        let basePrice: Double
        switch symbol {
        case "BTC":
            basePrice = 45000.0
        case "ETH":
            basePrice = 3000.0
        default:
            basePrice = 100.0
        }

        var prices: [Double] = []
        var currentPrice = basePrice

        for _ in 0..<count {
            let change = Double.random(in: -0.02...0.02)
            currentPrice *= (1.0 + change)
            prices.append(currentPrice)
        }

        return prices
    }

    private func generateMockPrice(for asset: String) -> Double {
        switch asset {
        case "BTC":
            return Double.random(in: 40000...50000)
        case "ETH":
            return Double.random(in: 2500...3500)
        case "ADA":
            return Double.random(in: 0.4...0.6)
        case "DOT":
            return Double.random(in: 6...10)
        case "LINK":
            return Double.random(in: 12...18)
        default:
            return Double.random(in: 50...150)
        }
    }

    private func calculateRSI(prices: [Double]) -> Double {
        guard prices.count >= 14 else { return 50.0 }

        let gains = zip(prices.dropFirst(), prices).map { current, previous in
            max(current - previous, 0.0)
        }

        let losses = zip(prices.dropFirst(), prices).map { current, previous in
            max(previous - current, 0.0)
        }

        let avgGain = gains.prefix(14).reduce(0, +) / 14.0
        let avgLoss = losses.prefix(14).reduce(0, +) / 14.0

        guard avgLoss > 0 else { return 100.0 }

        let rs = avgGain / avgLoss
        let rsi = 100.0 - (100.0 / (1.0 + rs))

        return rsi
    }

    private func calculateMovingAverage(prices: [Double], period: Int) -> Double {
        guard prices.count >= period else { return prices.last ?? 0.0 }

        let recentPrices = Array(prices.suffix(period))
        return recentPrices.reduce(0, +) / Double(recentPrices.count)
    }
}

public class MockExecutionEngine: ExecutionEngineProtocol {
    private let mockResults: [ExecutionResult]
    private let mockMarketCondition: MarketCondition

    public init(
        mockResults: [ExecutionResult] = [],
        mockMarketCondition: MarketCondition = MarketCondition(
            rsi: 50.0,
            priceVsMA30: 1.0,
            isOverheated: false,
            shouldDelay: false
        )
    ) {
        self.mockResults = mockResults
        self.mockMarketCondition = mockMarketCondition
    }

    public func executePlan(_ plan: AllocationPlan, dryRun: Bool) async throws -> [ExecutionResult] {
        return mockResults
    }

    public func analyzeMarketConditions() async throws -> MarketCondition {
        return mockMarketCondition
    }

    public func placeMakerOrder(asset: String, quantity: Double, exchange: String, dryRun: Bool) async throws -> ExecutionResult {
        let mockPrice = Double.random(in: 100...1000)
        return ExecutionResult(
            asset: asset,
            quantity: quantity,
            price: mockPrice,
            exchange: exchange,
            success: true
        )
    }
}
