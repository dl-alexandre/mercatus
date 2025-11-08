// PortfolioEnvironment for reinforcement learning-based portfolio optimization
// Implements portfolio rebalancing with transaction costs and risk-adjusted rewards

import Foundation
import MLX
import Utils

public class PortfolioEnvironment: Environment {
    private let historicalData: [[Float]]
    private let transactionCost: Float
    private var currentStep: Int
    private var portfolioValue: Float
    private var portfolioWeights: [Float]
    private var marketFeatures: Int

    public init(historicalData: [[Float]], transactionCost: Float = 0.001, initialCapital: Float = 1000000) {
        self.historicalData = historicalData
        self.transactionCost = transactionCost
        self.currentStep = 0
        self.portfolioValue = initialCapital
        self.portfolioWeights = Array(repeating: 1.0 / Float(historicalData[0].count), count: historicalData[0].count)
        self.marketFeatures = historicalData[0].count
    }

    public var actionSpaceSize: Int { marketFeatures }  // One action per asset, representing concentration
    public var observationSpaceSize: Int { marketFeatures + marketFeatures } // portfolio + market state

    public func reset() -> [Float] {
        currentStep = 0
        portfolioValue = 1000000
        portfolioWeights = Array(repeating: 1.0 / Float(marketFeatures), count: marketFeatures)
        return getObservation()
    }

    public func step(action: Int) -> (observation: [Float], reward: Float, done: Bool, info: [String: Any]) {
        // Decode action: action index represents asset to concentrate in
        var newWeights: [Float] = Array(repeating: 0.1, count: marketFeatures)
        if action < marketFeatures {
            newWeights[action] = 0.8
        }

        // Calculate transaction costs
        let turnover = zip(portfolioWeights, newWeights).map { abs($0 - $1) }.reduce(0.0, +)
        let transactionCostAmount = turnover * transactionCost * portfolioValue

        // Update portfolio
        portfolioWeights = newWeights
        let returns = calculateReturns()
        portfolioValue *= (1 + returns)
        portfolioValue -= transactionCostAmount

        // Calculate reward (risk-adjusted returns)
        let volatility = estimateVolatility()
        let reward = (returns / max(volatility, 0.001)) - (0.1 * transactionCostAmount / portfolioValue)

        currentStep += 1
        let done = currentStep >= historicalData.count

        return (getObservation(), reward, done, [
            "portfolio_value": portfolioValue,
            "transaction_cost": transactionCostAmount,
            "returns": returns,
            "volatility": volatility
        ])
    }

    private func getObservation() -> [Float] {
        guard currentStep < historicalData.count else { return [] }
        return portfolioWeights + historicalData[currentStep]
    }

    private func calculateReturns() -> Float {
        guard currentStep < historicalData.count else { return 0 }
        let currentPrices = historicalData[currentStep]
        let prevPrices = currentStep > 0 ? historicalData[currentStep - 1] : currentPrices
        let assetReturns = zip(currentPrices, prevPrices).map { ($0 - $1) / max($1, 0.001) }
        return zip(portfolioWeights, assetReturns).map(*).reduce(0, +)
    }

    private func estimateVolatility() -> Float {
        // Simple volatility estimate from recent data
        let windowSize = min(20, historicalData.count)
        let start = max(0, currentStep - windowSize)
        let windowData = Array(historicalData[start...currentStep])
        if windowData.count < 2 { return 0.02 }

        var allReturns: [Float] = []
        for i in 1..<windowData.count {
            let currentPrices = windowData[i]
            let prevPrices = windowData[i-1]
            let assetReturns = zip(currentPrices, prevPrices).map { ($0 - $1) / max($1, 0.001) }
            allReturns.append(contentsOf: assetReturns)
        }

        let mean = allReturns.reduce(0, +) / Float(allReturns.count)
        let variance = allReturns.map { pow($0 - mean, 2) }.reduce(0, +) / Float(allReturns.count)
        return sqrt(variance)
    }
}
