// Demo showing portfolio optimization using reinforcement learning
// Integrates with SmartVestor for intelligent allocation decisions

import Foundation
import Utils

public class PortfolioRLDemo {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func runPortfolioOptimizationDemo() async {
        logger.info(component: "PortfolioRLDemo", event: "Starting portfolio RL optimization demo")

        // Mock historical data for 3 assets (BTC, ETH, SOL) over 50 time steps
        let historicalData = generateMockHistoricalData(assetCount: 3, timeSteps: 50)

        // Initialize portfolio environment
        let env = PortfolioEnvironment(historicalData: historicalData, transactionCost: 0.001)

        // Initialize RL agent
        let observationSize = env.observationSpaceSize
        let actionSize = env.actionSpaceSize
        let agent = PPOAgent(observationSize: observationSize, actionSize: actionSize, logger: logger)

        logger.info(component: "PortfolioRLDemo", event: "Training RL agent",
                   data: ["observationSize": String(observationSize), "actionSize": String(actionSize)])

        // Train the agent
        await agent.train(env: env, numEpisodes: 100, maxSteps: 40)  // Shorter for demo

        logger.info(component: "PortfolioRLDemo", event: "Training completed, evaluating performance")

        // Evaluate performance
        let performanceMetrics = evaluatePortfolioPerformance(agent: agent, env: env)
        logger.info(component: "PortfolioRLDemo", event: "Portfolio optimization results",
                   data: [
                       "finalPortfolioValue": String(performanceMetrics.finalValue),
                       "totalReturn": String(performanceMetrics.totalReturn),
                       "sharpeRatio": String(performanceMetrics.sharpeRatio),
                       "maxDrawdown": String(performanceMetrics.maxDrawdown)
                   ])

        logger.info(component: "PortfolioRLDemo", event: "Demo completed successfully")
    }

    private func generateMockHistoricalData(assetCount: Int, timeSteps: Int) -> [[Float]] {
        var data: [[Float]] = []
        var prices: [Float] = Array(repeating: 100.0, count: assetCount)  // Start at $100 each

        for _ in 0..<timeSteps {
            // Add some random walk with drift
            for i in 0..<assetCount {
                let drift = Float.random(in: -0.02...0.03)  // -2% to +3% daily change
                prices[i] *= (1.0 + drift)
            }
            data.append(prices)
        }

        return data
    }

    private func evaluatePortfolioPerformance(agent: PPOAgent, env: PortfolioEnvironment) -> (finalValue: Float, totalReturn: Float, sharpeRatio: Float, maxDrawdown: Float) {
        var obs = env.reset()
        var portfolioValues: [Float] = [1000000]  // Initial capital
        var done = false
        var step = 0

        while !done && step < 40 {
            let (action, _) = agent.getAction(observation: obs)
            let (nextObs, _, isDone, info) = env.step(action: action)

            if let value = info["portfolio_value"] as? Float {
                portfolioValues.append(value)
            }

            obs = nextObs
            done = isDone
            step += 1
        }

        let finalValue = portfolioValues.last ?? 1000000
        let totalReturn = (finalValue - 1000000) / 1000000

        // Calculate Sharpe ratio (simplified)
        let returns = portfolioValues.enumerated().dropFirst().map { (i, value) in
            (value - portfolioValues[i-1]) / portfolioValues[i-1]
        }
        let avgReturn = returns.reduce(0, +) / Float(returns.count)
        let volatility = sqrt(returns.map { pow($0 - avgReturn, 2) }.reduce(0, +) / Float(returns.count))
        let sharpeRatio = volatility > 0 ? avgReturn / volatility : 0

        // Calculate max drawdown
        var maxDrawdown: Float = 0
        var peak = portfolioValues[0]
        for value in portfolioValues {
            if value > peak {
                peak = value
            }
            let drawdown = (peak - value) / peak
            maxDrawdown = max(maxDrawdown, drawdown)
        }

        return (finalValue, totalReturn, sharpeRatio * sqrt(252), maxDrawdown)  // Annualized Sharpe
    }
}
