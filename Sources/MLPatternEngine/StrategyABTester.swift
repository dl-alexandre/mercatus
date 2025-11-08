// A/B Testing framework for portfolio strategies
// Statistical comparison of ML-driven investment strategies

import Foundation
import Utils


public struct ABTestResult {
    public let strategyAMetrics: [String: Float]
    public let strategyBMetrics: [String: Float]
    public let significantDifferences: [String: [String: Any]]
    public let testPeriodDays: Int
    public let confidenceLevel: Float
    public let sampleSize: Int
}

public class StrategyABTester {
    private let strategyA: PortfolioStrategy
    private let strategyB: PortfolioStrategy
    private let testPeriodDays: Int
    private let backtester: PortfolioBacktester
    private let logger: StructuredLogger

    public init(strategyA: PortfolioStrategy, strategyB: PortfolioStrategy, testPeriodDays: Int = 30, backtester: PortfolioBacktester, logger: StructuredLogger) {
        self.strategyA = strategyA
        self.strategyB = strategyB
        self.testPeriodDays = testPeriodDays
        self.backtester = backtester
        self.logger = logger
    }

    public func runABTest(historicalData: [[Float]], confidenceLevel: Float = 0.95) -> ABTestResult {
        logger.info(component: "StrategyABTester", event: "Starting A/B test",
                   data: ["testPeriodDays": String(testPeriodDays), "confidenceLevel": String(confidenceLevel)])

        // Split data for out-of-sample testing (assuming daily data)
        let splitPoint = historicalData.count - testPeriodDays
        _ = Array(historicalData[0..<splitPoint])
        let testData = Array(historicalData[splitPoint..<historicalData.count])

        // Run both strategies
        let resultsA = backtester.runBacktest(strategy: strategyA, historicalData: testData, rebalanceFrequency: 1)
        let resultsB = backtester.runBacktest(strategy: strategyB, historicalData: testData, rebalanceFrequency: 1)

        // Calculate performance metrics
        let metricsA = backtester.calculatePerformanceMetrics(results: resultsA)
        let metricsB = backtester.calculatePerformanceMetrics(results: resultsB)

        // Statistical significance testing
        let significantDifferences = performStatisticalTests(
            resultsA: resultsA,
            resultsB: resultsB,
            confidenceLevel: confidenceLevel
        )

        let result = ABTestResult(
            strategyAMetrics: metricsA,
            strategyBMetrics: metricsB,
            significantDifferences: significantDifferences,
            testPeriodDays: testPeriodDays,
            confidenceLevel: confidenceLevel,
            sampleSize: testData.count
        )

        logger.info(component: "StrategyABTester", event: "A/B test completed",
                   data: [
                       "significantDifferences": String(significantDifferences.count),
                       "strategyASharpe": String(metricsA["sharpeRatio"] ?? 0),
                       "strategyBSharpe": String(metricsB["sharpeRatio"] ?? 0)
                   ])

        return result
    }

    private func performStatisticalTests(resultsA: [PortfolioBacktestResult], resultsB: [PortfolioBacktestResult], confidenceLevel: Float) -> [String: [String: Any]] {
        var significantDifferences: [String: [String: Any]] = [:]

        // Extract daily returns
        let returnsA = resultsA.map { $0.returns }
        let returnsB = resultsB.map { $0.returns }

        // Test key metrics
        let metricsToTest = ["sharpeRatio", "totalReturn", "maxDrawdown", "winRate"]

        for metric in metricsToTest {
            let valueA = resultsA.isEmpty ? 0 : calculateMetricValue(results: resultsA, metric: metric)
            let valueB = resultsB.isEmpty ? 0 : calculateMetricValue(results: resultsB, metric: metric)

            // Perform t-test on returns (proxy for metric comparison)
            let (tStatistic, pValue) = performTTest(sample1: returnsA, sample2: returnsB)

            let isSignificant = pValue < (1.0 - confidenceLevel)

            if isSignificant {
                significantDifferences[metric] = [
                    "strategyA": valueA,
                    "strategyB": valueB,
                    "pValue": pValue,
                    "tStatistic": tStatistic,
                    "significant": true
                ]
            }
        }

        return significantDifferences
    }

    private func calculateMetricValue(results: [PortfolioBacktestResult], metric: String) -> Float {
        switch metric {
        case "sharpeRatio":
            let returns = results.map { $0.returns }
            let count = Float(returns.count)
            let avgReturn = returns.reduce(0, +) / count
            let squaredDiffs = returns.map { pow($0 - avgReturn, 2) }
            let variance = squaredDiffs.reduce(0, +) / count
            let volatility = sqrtf(variance)
            return volatility > 0 ? avgReturn / volatility : 0

        case "totalReturn":
            guard let firstValue = results.first?.portfolioValue,
                  let lastValue = results.last?.portfolioValue else { return 0 }
            return (lastValue - firstValue) / firstValue

        case "maxDrawdown":
            let values = results.map { $0.portfolioValue }
            return backtester.calculateMaxDrawdown(values: values)

        case "winRate":
            let winningTrades = results.filter { $0.returns > 0 }.count
            return Float(winningTrades) / Float(results.count)

        default:
            return 0
        }
    }

    private func performTTest(sample1: [Float], sample2: [Float]) -> (tStatistic: Float, pValue: Float) {
        // Simplified t-test implementation
        let mean1 = sample1.reduce(0, +) / Float(sample1.count)
        let mean2 = sample2.reduce(0, +) / Float(sample2.count)

        let var1 = sample1.map { pow($0 - mean1, 2) }.reduce(0, +) / Float(sample1.count - 1)
        let var2 = sample2.map { pow($0 - mean2, 2) }.reduce(0, +) / Float(sample2.count - 1)

        let pooledVar = ((Float(sample1.count - 1) * var1) + (Float(sample2.count - 1) * var2)) /
                       Float(sample1.count + sample2.count - 2)

        let se = sqrt(pooledVar * (1.0 / Float(sample1.count) + 1.0 / Float(sample2.count)))
        let tStatistic = se > 0 ? (mean1 - mean2) / se : 0

        // Approximate p-value using t-distribution (simplified)
        let df = Float(sample1.count + sample2.count - 2)
        let pValue = 2 * (1 - tCDF(t: abs(tStatistic), df: df))  // Two-tailed

        return (tStatistic, pValue)
    }

    private func tCDF(t: Float, df: Float) -> Float {
        // Simplified CDF approximation for t-distribution
        // For large df, approaches normal distribution
        if df > 30 {
            // Normal CDF approximation
            let x = t / sqrtf(2.0)
            return 0.5 * (1.0 + erf(x))
        } else {
            // Very simplified approximation
            let x = t / sqrtf(df)
            return 1.0 / (1.0 + exp(-x))
        }
    }

    public func generateABTestReport(result: ABTestResult) -> String {
        var report = """
        === A/B Test Report ===
        Test Period: \(result.testPeriodDays) days
        Confidence Level: \(String(format: "%.2f", result.confidenceLevel))
        Sample Size: \(result.sampleSize)

        Strategy A Metrics:
        """

        for (metric, value) in result.strategyAMetrics {
            report += "\n  \(metric): \(String(format: "%.4f", value))"
        }

        report += "\n\nStrategy B Metrics:"
        for (metric, value) in result.strategyBMetrics {
            report += "\n  \(metric): \(String(format: "%.4f", value))"
        }

        report += "\n\nSignificant Differences (\(String(format: "%.0f", result.confidenceLevel * 100))% confidence):"
        if result.significantDifferences.isEmpty {
            report += "\n  No significant differences found"
        } else {
            for (metric, details) in result.significantDifferences {
                report += "\n  \(metric):"
                report += "\n    Strategy A: \(String(format: "%.4f", details["strategyA"] as? Float ?? 0))"
                report += "\n    Strategy B: \(String(format: "%.4f", details["strategyB"] as? Float ?? 0))"
                report += "\n    p-value: \(String(format: "%.4f", details["pValue"] as? Float ?? 0))"
            }
        }

        return report
    }
}
