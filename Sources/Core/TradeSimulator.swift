import Foundation
import Utils

public actor TradeSimulator {
    public struct Configuration: Sendable, Equatable {
        public let initialBalance: Decimal
        public let feePercentagePerTrade: Decimal
        public let tradeAllocationPercentage: Decimal

        public init(
            initialBalance: Decimal = 10_000,
            feePercentagePerTrade: Decimal = 0.001,
            tradeAllocationPercentage: Decimal = 0.1
        ) {
            precondition(initialBalance > 0, "initialBalance must be > 0")
            precondition(feePercentagePerTrade >= 0, "feePercentagePerTrade must be >= 0")
            precondition(tradeAllocationPercentage > 0 && tradeAllocationPercentage <= 1,
                        "tradeAllocationPercentage must be between 0 and 1")
            self.initialBalance = initialBalance
            self.feePercentagePerTrade = feePercentagePerTrade
            self.tradeAllocationPercentage = tradeAllocationPercentage
        }
    }

    public struct Statistics: Sendable, Equatable {
        public let totalTrades: Int
        public let successfulTrades: Int
        public let totalProfit: Decimal
        public let currentBalance: Decimal
        public let successRate: Double

        public init(
            totalTrades: Int,
            successfulTrades: Int,
            totalProfit: Decimal,
            currentBalance: Decimal,
            successRate: Double
        ) {
            self.totalTrades = totalTrades
            self.successfulTrades = successfulTrades
            self.totalProfit = totalProfit
            self.currentBalance = currentBalance
            self.successRate = successRate
        }
    }

    private let config: Configuration
    private let logger: StructuredLogger?
    private let componentName = "TradeSimulator"

    private var currentBalance: Decimal
    private var totalTrades: Int = 0
    private var successfulTrades: Int = 0
    private var totalProfit: Decimal = 0

    public init(config: Configuration, logger: StructuredLogger? = nil) {
        self.config = config
        self.logger = logger
        self.currentBalance = config.initialBalance
    }

    public func simulateTrade(_ analysis: SpreadAnalysis) {
        guard analysis.isProfitable else { return }

        let tradeAmount = currentBalance * config.tradeAllocationPercentage

        let buyFee = tradeAmount * config.feePercentagePerTrade
        let amountAfterBuyFee = tradeAmount - buyFee

        let cryptoAmount = amountAfterBuyFee / analysis.buyPrice

        let sellProceeds = cryptoAmount * analysis.sellPrice
        let sellFee = sellProceeds * config.feePercentagePerTrade
        let netProceeds = sellProceeds - sellFee

        let profit = netProceeds - tradeAmount
        let profitPercentage = (profit / tradeAmount)

        let isSuccessful = profit > 0

        totalTrades += 1
        if isSuccessful {
            successfulTrades += 1
            currentBalance += profit
            totalProfit += profit
        } else {
            currentBalance += profit
            totalProfit += profit
        }

        logTrade(
            analysis: analysis,
            tradeAmount: tradeAmount,
            buyFee: buyFee,
            sellFee: sellFee,
            profit: profit,
            profitPercentage: profitPercentage,
            isSuccessful: isSuccessful
        )
    }

    public func statistics() -> Statistics {
        let successRate = totalTrades > 0 ? Double(successfulTrades) / Double(totalTrades) : 0.0
        return Statistics(
            totalTrades: totalTrades,
            successfulTrades: successfulTrades,
            totalProfit: totalProfit,
            currentBalance: currentBalance,
            successRate: successRate
        )
    }

    public func reset() {
        currentBalance = config.initialBalance
        totalTrades = 0
        successfulTrades = 0
        totalProfit = 0
    }

    public nonisolated func consumeProfitableStreams(from detector: SpreadDetector) -> Task<Void, Never> {
        let selfReference = self
        return Task {
            for await analysis in await detector.analysisStream() {
                guard analysis.isProfitable else { continue }
                await selfReference.simulateTrade(analysis)
            }
        }
    }

    private func logTrade(
        analysis: SpreadAnalysis,
        tradeAmount: Decimal,
        buyFee: Decimal,
        sellFee: Decimal,
        profit: Decimal,
        profitPercentage: Decimal,
        isSuccessful: Bool
    ) {
        logger?.info(
            component: componentName,
            event: "trade_simulated",
            data: [
                "symbol": analysis.symbol,
                "buy_exchange": analysis.buyExchange,
                "sell_exchange": analysis.sellExchange,
                "buy_price": decimalString(analysis.buyPrice),
                "sell_price": decimalString(analysis.sellPrice),
                "trade_amount": decimalString(tradeAmount),
                "buy_fee": decimalString(buyFee),
                "sell_fee": decimalString(sellFee),
                "profit": decimalString(profit),
                "profit_percentage": decimalString(profitPercentage * 100),
                "successful": isSuccessful ? "true" : "false",
                "total_trades": String(totalTrades),
                "current_balance": decimalString(currentBalance),
                "total_profit": decimalString(totalProfit)
            ]
        )
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
