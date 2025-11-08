import Foundation
import Utils

public struct PortfolioWeights {
    public let symbols: [String]
    public let weights: [Double]
    public let expectedReturn: Double
    public let expectedVolatility: Double
    public let sharpeRatio: Double

    public init(symbols: [String], weights: [Double], expectedReturn: Double, expectedVolatility: Double, sharpeRatio: Double) {
        self.symbols = symbols
        self.weights = weights
        self.expectedReturn = expectedReturn
        self.expectedVolatility = expectedVolatility
        self.sharpeRatio = sharpeRatio
    }
}

public class MeanVarianceOptimizer {
    private let logger: StructuredLogger
    private let riskFreeRate: Double
    private let maxWeight: Double
    private let minWeight: Double

    public init(logger: StructuredLogger, riskFreeRate: Double = 0.02, maxWeight: Double = 0.25, minWeight: Double = 0.0) {
        self.logger = logger
        self.riskFreeRate = riskFreeRate
        self.maxWeight = maxWeight
        self.minWeight = minWeight
    }

    public func optimize(
        symbols: [String],
        predictedReturns: [Double],
        predictedVolatilities: [Double],
        correlationMatrix: [[Double]]? = nil
    ) throws -> PortfolioWeights {
        guard symbols.count == predictedReturns.count && symbols.count == predictedVolatilities.count else {
            throw OptimizationError.invalidInput("Symbols, returns, and volatilities must have same length")
        }

        let n = symbols.count

        let covarianceMatrix: [[Double]]
        if let corrMatrix = correlationMatrix {
            guard corrMatrix.count == n && corrMatrix.allSatisfy({ $0.count == n }) else {
                throw OptimizationError.invalidInput("Correlation matrix dimensions must match number of assets")
            }
            covarianceMatrix = computeCovarianceMatrix(volatilities: predictedVolatilities, correlations: corrMatrix)
        } else {
            covarianceMatrix = computeDiagonalCovariance(volatilities: predictedVolatilities)
        }

        let weights = solveMeanVarianceOptimization(
            returns: predictedReturns,
            covariance: covarianceMatrix,
            riskFreeRate: riskFreeRate
        )

        let constrainedWeights = applyConstraints(weights: weights, minWeight: minWeight, maxWeight: maxWeight)
        let normalizedWeights = normalizeWeights(constrainedWeights)

        let expectedReturn = computeExpectedReturn(weights: normalizedWeights, returns: predictedReturns)
        let expectedVolatility = computeExpectedVolatility(weights: normalizedWeights, covariance: covarianceMatrix)
        let sharpeRatio = (expectedReturn - riskFreeRate) / expectedVolatility

        logger.info(component: "MeanVarianceOptimizer", event: "Portfolio optimized", data: [
            "expectedReturn": String(expectedReturn),
            "expectedVolatility": String(expectedVolatility),
            "sharpeRatio": String(sharpeRatio)
        ])

        return PortfolioWeights(
            symbols: symbols,
            weights: normalizedWeights,
            expectedReturn: expectedReturn,
            expectedVolatility: expectedVolatility,
            sharpeRatio: sharpeRatio
        )
    }

    private func computeCovarianceMatrix(volatilities: [Double], correlations: [[Double]]) -> [[Double]] {
        let n = volatilities.count
        var covariance = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in 0..<n {
                covariance[i][j] = volatilities[i] * volatilities[j] * correlations[i][j]
            }
        }

        return covariance
    }

    private func computeDiagonalCovariance(volatilities: [Double]) -> [[Double]] {
        let n = volatilities.count
        var covariance = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            covariance[i][i] = volatilities[i] * volatilities[i]
        }

        return covariance
    }

    private func solveMeanVarianceOptimization(returns: [Double], covariance: [[Double]], riskFreeRate: Double) -> [Double] {
        let n = returns.count
        let excessReturns = returns.map { $0 - riskFreeRate }

        var invCov = invertMatrix(covariance)
        let numerator = matrixVectorMultiply(invCov, excessReturns)
        let denominator = vectorDotProduct(excessReturns, numerator)

        if abs(denominator) < 1e-10 {
            return Array(repeating: 1.0 / Double(n), count: n)
        }

        return numerator.map { $0 / denominator }
    }

    private func invertMatrix(_ matrix: [[Double]]) -> [[Double]] {
        let n = matrix.count
        var inv = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            inv[i][i] = 1.0 / matrix[i][i]
        }

        return inv
    }

    private func matrixVectorMultiply(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        return matrix.map { row in
            zip(row, vector).map(*).reduce(0, +)
        }
    }

    private func vectorDotProduct(_ a: [Double], _ b: [Double]) -> Double {
        return zip(a, b).map(*).reduce(0, +)
    }

    private func applyConstraints(weights: [Double], minWeight: Double, maxWeight: Double) -> [Double] {
        return weights.map { max(minWeight, min(maxWeight, $0)) }
    }

    private func normalizeWeights(_ weights: [Double]) -> [Double] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1.0 / Double(weights.count), count: weights.count)
        }
        return weights.map { $0 / sum }
    }

    private func computeExpectedReturn(weights: [Double], returns: [Double]) -> Double {
        return zip(weights, returns).map(*).reduce(0, +)
    }

    private func computeExpectedVolatility(weights: [Double], covariance: [[Double]]) -> Double {
        var variance = 0.0
        let n = weights.count

        for i in 0..<n {
            for j in 0..<n {
                variance += weights[i] * weights[j] * covariance[i][j]
            }
        }

        return sqrt(max(0.0, variance))
    }
}

public enum OptimizationError: Error {
    case invalidInput(String)

    public var localizedDescription: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}
