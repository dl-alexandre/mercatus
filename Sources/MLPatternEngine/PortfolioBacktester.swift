// Portfolio backtesting framework for ML-driven strategies
// Comprehensive backtesting with transaction costs, performance metrics, and risk analysis

import Foundation
import Utils

public struct PortfolioBacktestResult {
    public let portfolioValue: Float
    public let weights: [Float]
    public let transactionCost: Float
    public let turnover: Float
    public let returns: Float
    public let timestamp: Date
}

public protocol PortfolioStrategy {
    func generateWeights(historicalData: [[Float]], currentStep: Int) -> [Float]
}

public class PortfolioBacktester {
    private let initialCapital: Float
    private let transactionCost: Float
    private var portfolioHistory: [PortfolioBacktestResult] = []
    private let logger: StructuredLogger

    public init(initialCapital: Float = 1000000, transactionCost: Float = 0.001, logger: StructuredLogger) {
        self.initialCapital = initialCapital
        self.transactionCost = transactionCost
        self.logger = logger
    }

    public func runBacktest(strategy: PortfolioStrategy, historicalData: [[Float]], rebalanceFrequency: Int = 21) -> [PortfolioBacktestResult] {
        logger.info(component: "PortfolioBacktester", event: "Starting backtest",
                   data: [
                       "initialCapital": String(initialCapital),
                       "transactionCost": String(transactionCost),
                       "dataPoints": String(historicalData.count),
                       "rebalanceFrequency": String(rebalanceFrequency)
                   ])

        portfolioHistory.removeAll()
        var currentWeights = Array(repeating: 1.0 / Float(historicalData[0].count), count: historicalData[0].count)
        var currentValue = initialCapital

        for i in stride(from: rebalanceFrequency, to: historicalData.count, by: rebalanceFrequency) {
            let currentData = Array(historicalData[0..<i])

            // Strategy generates new weights
            let newWeights = strategy.generateWeights(historicalData: currentData, currentStep: i)

            // Calculate transaction costs and turnover
            let turnover = calculateTurnover(currentWeights: currentWeights, newWeights: newWeights)
            let transactionCostAmount = turnover * transactionCost * currentValue

            // Update portfolio value based on returns
            let periodReturns = calculatePeriodReturns(data: historicalData, startIndex: i - rebalanceFrequency, endIndex: i)
            let weightedReturns = zip(currentWeights, periodReturns).map(*).reduce(0, +)
            currentValue *= (1 + weightedReturns)
            currentValue -= transactionCostAmount

            // Update weights
            currentWeights = newWeights

            let result = PortfolioBacktestResult(
                portfolioValue: currentValue,
                weights: currentWeights,
                transactionCost: transactionCostAmount,
                turnover: turnover,
                returns: weightedReturns,
                timestamp: Date()  // In real implementation, use actual timestamps
            )

            portfolioHistory.append(result)
        }

        logger.info(component: "PortfolioBacktester", event: "Backtest completed",
                   data: ["totalPeriods": String(portfolioHistory.count)])

        return portfolioHistory
    }

    public func calculatePerformanceMetrics(results: [PortfolioBacktestResult]) -> [String: Float] {
        guard !results.isEmpty else { return [:] }

        let finalValue = results.last!.portfolioValue
        let totalReturn = (finalValue - initialCapital) / initialCapital

        // Calculate daily returns (simplified - assumes daily rebalancing)
        let returns = results.map { $0.returns }
        let avgReturn = returns.reduce(0, +) / Float(returns.count)

        // Volatility (standard deviation of returns)
        let variance = returns.map { pow($0 - avgReturn, 2) }.reduce(0, +) / Float(returns.count)
        let volatility = sqrt(variance)

        // Sharpe ratio (annualized, assuming risk-free rate of 2%)
        let riskFreeRate: Float = 0.02 / 252  // Daily risk-free rate
        let excessReturns = returns.map { $0 - riskFreeRate }
        let avgExcessReturn = excessReturns.reduce(0, +) / Float(excessReturns.count)
        let sharpeRatio = volatility > 0 ? (avgExcessReturn / volatility) * sqrt(252) : 0

        // Maximum drawdown
        var maxDrawdown: Float = 0
        var peak = initialCapital
        for result in results {
            if result.portfolioValue > peak {
                peak = result.portfolioValue
            }
            let drawdown = (peak - result.portfolioValue) / peak
            maxDrawdown = max(maxDrawdown, drawdown)
        }

        // Win rate
        let winningTrades = returns.filter { $0 > 0 }.count
        let winRate = Float(winningTrades) / Float(returns.count)

        // Total transaction costs
        let totalCosts = results.map { $0.transactionCost }.reduce(0, +)

        // Average turnover
        let avgTurnover = results.map { $0.turnover }.reduce(0, +) / Float(results.count)

        return [
            "totalReturn": totalReturn,
            "annualizedReturn": pow(1 + totalReturn, 1.0 / (Float(results.count) / 252)) - 1,
            "volatility": volatility * sqrt(252),  // Annualized
            "sharpeRatio": sharpeRatio,
            "maxDrawdown": maxDrawdown,
            "winRate": winRate,
            "totalTransactionCosts": totalCosts,
            "averageTurnover": avgTurnover,
            "finalValue": finalValue
        ]
    }

    public func calculateMaxDrawdown(values: [Float]) -> Float {
        var maxDrawdown: Float = 0
        var peak = values[0]

        for value in values {
            if value > peak {
                peak = value
            }
            let drawdown = (peak - value) / peak
            maxDrawdown = max(maxDrawdown, drawdown)
        }

        return maxDrawdown
    }

    private func calculateTurnover(currentWeights: [Float], newWeights: [Float]) -> Float {
        let changes = zip(currentWeights, newWeights).map { abs($0 - $1) }
        return changes.reduce(0, +) / 2  // Divide by 2 because each trade affects two sides
    }

    private func calculatePeriodReturns(data: [[Float]], startIndex: Int, endIndex: Int) -> [Float] {
        guard startIndex < endIndex, endIndex < data.count else { return [] }

        let startPrices = data[startIndex]
        let endPrices = data[endIndex]

        return zip(startPrices, endPrices).map { ($1 - $0) / max($0, 0.001) }
    }

    public func compareStrategies(strategies: [String: PortfolioStrategy], historicalData: [[Float]], rebalanceFrequency: Int = 21) -> [String: [String: Float]] {
        var results: [String: [String: Float]] = [:]

        for (name, strategy) in strategies {
            let backtestResults = runBacktest(strategy: strategy, historicalData: historicalData, rebalanceFrequency: rebalanceFrequency)
            let metrics = calculatePerformanceMetrics(results: backtestResults)
            results[name] = metrics

            logger.info(component: "PortfolioBacktester", event: "Strategy comparison",
                       data: [
                           "strategy": name,
                           "sharpeRatio": String(metrics["sharpeRatio"] ?? 0),
                           "totalReturn": String(metrics["totalReturn"] ?? 0),
                           "maxDrawdown": String(metrics["maxDrawdown"] ?? 0)
                       ])
        }

        return results
    }
}

// Example strategy implementations
public class EqualWeightStrategy: PortfolioStrategy {
    private let nAssets: Int

    public init(nAssets: Int) {
        self.nAssets = nAssets
    }

    public func generateWeights(historicalData: [[Float]], currentStep: Int) -> [Float] {
        return Array(repeating: 1.0 / Float(nAssets), count: nAssets)
    }
}

public class MomentumStrategy: PortfolioStrategy {
    private let lookbackPeriod: Int

    public init(lookbackPeriod: Int = 20) {
        self.lookbackPeriod = lookbackPeriod
    }

    public func generateWeights(historicalData: [[Float]], currentStep: Int) -> [Float] {
        let nAssets = historicalData[0].count
        var weights = Array(repeating: Float(0), count: nAssets)

        // Calculate momentum (recent returns)
        for asset in 0..<nAssets {
            let startPrice = historicalData[max(0, currentStep - lookbackPeriod)][asset]
            let endPrice = historicalData[currentStep][asset]
            let momentum = (endPrice - startPrice) / max(startPrice, 0.001)

            weights[asset] = max(0, momentum)  // Only positive momentum
        }

        // Normalize weights
        let totalWeight = weights.reduce(0, +)
        if totalWeight > 0 {
            weights = weights.map { $0 / totalWeight }
        } else {
            // Fallback to equal weight
            weights = Array(repeating: 1.0 / Float(nAssets), count: nAssets)
        }

        return weights
    }
}
