import Foundation
import Core
import Utils

public protocol VolatilityPredictionProtocol {
    func predictVolatility(for symbol: String, historicalData: [MarketDataPoint], horizon: TimeInterval) async throws -> VolatilityPrediction
    func calculateGARCHParameters(returns: [Double]) async throws -> GARCHParameters
    func forecastVolatility(parameters: GARCHParameters, lastReturns: [Double], horizon: Int) async throws -> [Double]
}

public struct GARCHParameters {
    public let omega: Double      // Constant term
    public let alpha: Double      // ARCH coefficient (short-term)
    public let beta: Double       // GARCH coefficient (long-term)
    public let gamma: Double?     // Asymmetric term (GJR-GARCH)
    public let mu: Double         // Mean return
    public let logLikelihood: Double
    public let aic: Double
    public let bic: Double

    public init(omega: Double, alpha: Double, beta: Double, gamma: Double? = nil, mu: Double, logLikelihood: Double, aic: Double, bic: Double) {
        self.omega = omega
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
        self.mu = mu
        self.logLikelihood = logLikelihood
        self.aic = aic
        self.bic = bic
    }
}

public struct VolatilityPrediction {
    public let symbol: String
    public let timestamp: Date
    public let horizon: TimeInterval
    public let predictedVolatility: [Double]
    public let confidence: Double
    public let modelType: String
    public let parameters: GARCHParameters
    public let r2: Double
    public let mse: Double

    public init(symbol: String, timestamp: Date, horizon: TimeInterval, predictedVolatility: [Double], confidence: Double, modelType: String, parameters: GARCHParameters, r2: Double, mse: Double) {
        self.symbol = symbol
        self.timestamp = timestamp
        self.horizon = horizon
        self.predictedVolatility = predictedVolatility
        self.confidence = confidence
        self.modelType = modelType
        self.parameters = parameters
        self.r2 = r2
        self.mse = mse
    }
}

public class GARCHVolatilityPredictor: VolatilityPredictionProtocol {
    private let logger: StructuredLogger
    private let maxIterations = 1000
    private let tolerance = 1e-6

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictVolatility(for symbol: String, historicalData: [MarketDataPoint], horizon: TimeInterval) async throws -> VolatilityPrediction {
        guard historicalData.count >= 100 else {
            throw VolatilityPredictionError.insufficientData
        }

        // Calculate returns
        let returns = calculateReturns(from: historicalData)

        // Fit GARCH model
        let parameters = try await calculateGARCHParameters(returns: returns)

        // Forecast volatility
        let horizonDouble = horizon / 300
        let horizonSteps = horizonDouble.isFinite ? Swift.max(1, Int(horizonDouble.rounded())) : 1
        let forecastedVolatility = try await forecastVolatility(
            parameters: parameters,
            lastReturns: Array(returns.suffix(50)),
            horizon: horizonSteps
        )

        // Calculate model performance metrics
        let (r2, mse) = calculateModelPerformance(returns: returns, parameters: parameters)

        // Calculate confidence based on model fit
        let confidence = min(max(r2, 0.0), 1.0)

        logger.info(component: "GARCHVolatilityPredictor", event: "Generated volatility prediction", data: [
            "symbol": symbol,
            "horizon": String(horizon),
            "steps": String(horizonSteps),
            "confidence": String(confidence),
            "r2": String(r2)
        ])

        return VolatilityPrediction(
            symbol: symbol,
            timestamp: Date(),
            horizon: horizon,
            predictedVolatility: forecastedVolatility,
            confidence: confidence,
            modelType: "GARCH(1,1)",
            parameters: parameters,
            r2: r2,
            mse: mse
        )
    }

    public func calculateGARCHParameters(returns: [Double]) async throws -> GARCHParameters {
        guard returns.count >= 50 else {
            throw VolatilityPredictionError.insufficientData
        }

        // Initialize parameters
        var omega = 0.0001
        var alpha = 0.1
        var beta = 0.85
        var mu = returns.reduce(0, +) / Double(returns.count)

        // Calculate initial variance
        let meanReturn = mu
        let squaredReturns = returns.map { pow($0 - meanReturn, 2) }
        let variance = squaredReturns.reduce(0, +) / Double(squaredReturns.count)

        // Maximum Likelihood Estimation using iterative optimization
        var bestLogLikelihood = -Double.infinity
        var bestParameters = (omega: omega, alpha: alpha, beta: beta, mu: mu)

        for iteration in 0..<maxIterations {
            // Calculate conditional variances
            var conditionalVariances: [Double] = []
            var currentVariance = variance

            for i in 0..<returns.count {
                let returnValue = returns[i] - mu
                let squaredReturn = returnValue * returnValue

                currentVariance = omega + alpha * squaredReturn + beta * currentVariance
                conditionalVariances.append(max(currentVariance, 1e-8)) // Ensure positive variance
            }

            // Calculate log-likelihood
            let logLikelihood = calculateLogLikelihood(returns: returns, variances: conditionalVariances, mu: mu)

            if logLikelihood > bestLogLikelihood {
                bestLogLikelihood = logLikelihood
                bestParameters = (omega: omega, alpha: alpha, beta: beta, mu: mu)
            }

            // Check convergence
            if iteration > 0 && abs(logLikelihood - bestLogLikelihood) < tolerance {
                break
            }

            // Update parameters using gradient descent
            let gradients = calculateGradients(returns: returns, variances: conditionalVariances, mu: mu)
            let learningRate = 0.001 / (1.0 + Double(iteration) * 0.1)

            omega = max(omega + learningRate * gradients.omega, 1e-8)
            alpha = max(min(alpha + learningRate * gradients.alpha, 0.5), 0.0)
            beta = max(min(beta + learningRate * gradients.beta, 0.95), 0.0)
            mu = mu + learningRate * gradients.mu

            // Ensure alpha + beta < 1 for stationarity
            if alpha + beta >= 1.0 {
                let total = alpha + beta
                alpha = alpha / total * 0.99
                beta = beta / total * 0.99
            }
        }

        // Calculate final metrics
        let finalVariances = calculateConditionalVariances(
            returns: returns,
            omega: bestParameters.omega,
            alpha: bestParameters.alpha,
            beta: bestParameters.beta,
            mu: bestParameters.mu
        )

        let finalLogLikelihood = calculateLogLikelihood(
            returns: returns,
            variances: finalVariances,
            mu: bestParameters.mu
        )

        let n = returns.count
        let k = 4.0 // Number of parameters
        let aic = 2 * k - 2 * finalLogLikelihood
        let bic = k * log(Double(n)) - 2 * finalLogLikelihood

        // Calculate R-squared
        let r2 = calculateR2(returns: returns, variances: finalVariances)

        logger.debug(component: "GARCHVolatilityPredictor", event: "Fitted GARCH model", data: [
            "omega": String(bestParameters.omega),
            "alpha": String(bestParameters.alpha),
            "beta": String(bestParameters.beta),
            "mu": String(bestParameters.mu),
            "logLikelihood": String(finalLogLikelihood),
            "r2": String(r2)
        ])

        return GARCHParameters(
            omega: bestParameters.omega,
            alpha: bestParameters.alpha,
            beta: bestParameters.beta,
            gamma: nil,
            mu: bestParameters.mu,
            logLikelihood: finalLogLikelihood,
            aic: aic,
            bic: bic
        )
    }

    public func forecastVolatility(parameters: GARCHParameters, lastReturns: [Double], horizon: Int) async throws -> [Double] {
        guard !lastReturns.isEmpty else {
            throw VolatilityPredictionError.insufficientData
        }

        var forecastedVolatility: [Double] = []
        var currentVariance = calculateInitialVariance(returns: lastReturns, parameters: parameters)

        for _ in 1...horizon {
            // GARCH(1,1) forecast: h_t = omega + alpha * epsilon_{t-1}^2 + beta * h_{t-1}
            // For multi-step ahead, we use the expected value
            let expectedSquaredReturn = currentVariance
            currentVariance = parameters.omega + parameters.alpha * expectedSquaredReturn + parameters.beta * currentVariance

            // Convert variance to volatility (standard deviation)
            let volatility = sqrt(currentVariance)
            forecastedVolatility.append(volatility)
        }

        return forecastedVolatility
    }

    // MARK: - Private Methods

    private func calculateReturns(from dataPoints: [MarketDataPoint]) -> [Double] {
        guard dataPoints.count > 1 else { return [] }

        var returns: [Double] = []
        for i in 1..<dataPoints.count {
            let currentPrice = dataPoints[i].close
            let previousPrice = dataPoints[i-1].close

            if previousPrice > 0 {
                let returnValue = log(currentPrice / previousPrice)
                returns.append(returnValue)
            }
        }

        return returns
    }

    private func calculateConditionalVariances(returns: [Double], omega: Double, alpha: Double, beta: Double, mu: Double) -> [Double] {
        var variances: [Double] = []
        var currentVariance = returns.map { pow($0 - mu, 2) }.reduce(0, +) / Double(returns.count)

        for returnValue in returns {
            let squaredReturn = pow(returnValue - mu, 2)
            currentVariance = omega + alpha * squaredReturn + beta * currentVariance
            variances.append(max(currentVariance, 1e-8))
        }

        return variances
    }

    private func calculateLogLikelihood(returns: [Double], variances: [Double], mu: Double) -> Double {
        var logLikelihood = 0.0

        for i in 0..<returns.count {
            let returnValue = returns[i]
            let variance = variances[i]

            // Log-likelihood for normal distribution
            logLikelihood += -0.5 * (log(2 * Double.pi * variance) + pow(returnValue - mu, 2) / variance)
        }

        return logLikelihood
    }

    private func calculateGradients(returns: [Double], variances: [Double], mu: Double) -> (omega: Double, alpha: Double, beta: Double, mu: Double) {
        var omegaGrad = 0.0
        var alphaGrad = 0.0
        var betaGrad = 0.0
        var muGrad = 0.0

        for i in 0..<returns.count {
            let returnValue = returns[i]
            let variance = variances[i]
            let error = returnValue - mu
            let squaredError = error * error

            // Gradient for omega
            omegaGrad += 0.5 * (squaredError / (variance * variance) - 1.0 / variance)

            // Gradient for alpha
            alphaGrad += 0.5 * squaredError * (squaredError / (variance * variance) - 1.0 / variance)

            // Gradient for beta
            betaGrad += 0.5 * (squaredError / (variance * variance) - 1.0 / variance)

            // Gradient for mu
            muGrad += error / variance
        }

        return (omega: omegaGrad, alpha: alphaGrad, beta: betaGrad, mu: muGrad)
    }

    private func calculateInitialVariance(returns: [Double], parameters: GARCHParameters) -> Double {
        let meanReturn = parameters.mu
        let squaredReturns = returns.map { pow($0 - meanReturn, 2) }
        return squaredReturns.reduce(0, +) / Double(squaredReturns.count)
    }

    private func calculateModelPerformance(returns: [Double], parameters: GARCHParameters) -> (r2: Double, mse: Double) {
        let variances = calculateConditionalVariances(
            returns: returns,
            omega: parameters.omega,
            alpha: parameters.alpha,
            beta: parameters.beta,
            mu: parameters.mu
        )

        let squaredReturns = returns.map { pow($0 - parameters.mu, 2) }
        let meanSquaredReturn = squaredReturns.reduce(0, +) / Double(squaredReturns.count)

        // Calculate R-squared
        let ssRes = zip(squaredReturns, variances).map { pow($0 - $1, 2) }.reduce(0, +)
        let ssTot = squaredReturns.map { pow($0 - meanSquaredReturn, 2) }.reduce(0, +)
        let r2 = 1.0 - (ssRes / ssTot)

        // Calculate MSE
        let mse = ssRes / Double(squaredReturns.count)

        return (r2: max(r2, 0.0), mse: mse)
    }

    private func calculateR2(returns: [Double], variances: [Double]) -> Double {
        let squaredReturns = returns.map { pow($0, 2) }
        let meanSquaredReturn = squaredReturns.reduce(0, +) / Double(squaredReturns.count)

        let ssRes = zip(squaredReturns, variances).map { pow($0 - $1, 2) }.reduce(0, +)
        let ssTot = squaredReturns.map { pow($0 - meanSquaredReturn, 2) }.reduce(0, +)

        return max(1.0 - (ssRes / ssTot), 0.0)
    }
}

public enum VolatilityPredictionError: Error {
    case insufficientData
    case parameterEstimationFailed
    case forecastFailed
    case invalidParameters
}
