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
    private let logger: StructuredLogger

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]
    ) {
        self.config = config
        self.persistence = persistence
        self.exchangeConnectors = exchangeConnectors
        self.logger = StructuredLogger()
    }

    public func executePlan(_ plan: AllocationPlan, dryRun: Bool) async throws -> [ExecutionResult] {
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
            let orderBook = try await connector.getOrderBook(symbol: "\(asset)USDC")
            let bestBid = orderBook.bids.first?.price ?? 0.0
            let bestAsk = orderBook.asks.first?.price ?? 0.0

            let makerPrice = bestBid + (bestAsk - bestBid) * 0.1

            let order = try await connector.placeOrder(
                symbol: "\(asset)USDC",
                side: OrderSide.buy,
                type: OrderType.limit,
                quantity: quantity,
                price: makerPrice
            )

            let transaction = InvestmentTransaction(
                type: .buy,
                exchange: exchange,
                asset: asset,
                quantity: quantity,
                price: makerPrice,
                fee: quantity * makerPrice * 0.001,
                timestamp: Date(),
                metadata: [
                    "order_id": order.id,
                    "order_type": "maker"
                ]
            )

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
