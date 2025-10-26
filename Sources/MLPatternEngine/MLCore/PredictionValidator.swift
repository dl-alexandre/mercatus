import Foundation
import Core
import Utils

public protocol PredictionValidationProtocol {
    func validatePricePrediction(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> ValidationResult
    func validateVolatilityPrediction(prediction: VolatilityPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult
    func validateTrendClassification(classification: TrendClassification, actualData: [MarketDataPoint]) async throws -> ValidationResult
    func validateReversalPrediction(prediction: ReversalPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult
    func calculateModelMetrics(predictions: [PredictionResponse], actualData: [MarketDataPoint]) async throws -> ValidationModelMetrics
    func performBacktesting(modelType: ModelType, historicalData: [MarketDataPoint], lookbackPeriod: TimeInterval) async throws -> BacktestResult
    func performWalkForwardValidation(modelType: ModelType, historicalData: [MarketDataPoint], trainingWindow: TimeInterval, validationWindow: TimeInterval, stepSize: TimeInterval) async throws -> WalkForwardResult
    func trackPredictionAccuracy(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> AccuracyTrackingResult
}

public enum ModelType: String, CaseIterable, Codable {
    case pricePrediction = "PRICE_PREDICTION"
    case volatilityPrediction = "VOLATILITY_PREDICTION"
    case trendClassification = "TREND_CLASSIFICATION"
    case reversalPrediction = "REVERSAL_PREDICTION"
    case patternRecognition = "PATTERN_RECOGNITION"
}

public struct ValidationResult {
    public let modelType: ModelType
    public let timestamp: Date
    public let accuracy: Double
    public let precision: Double
    public let recall: Double
    public let f1Score: Double
    public let mae: Double // Mean Absolute Error
    public let mse: Double // Mean Squared Error
    public let rmse: Double // Root Mean Squared Error
    public let mape: Double // Mean Absolute Percentage Error
    public let directionalAccuracy: Double
    public let sharpeRatio: Double?
    public let maxDrawdown: Double?
    public let hitRate: Double
    public let confidence: Double
    public let validationPeriod: TimeInterval
    public let sampleSize: Int

    public init(modelType: ModelType, timestamp: Date, accuracy: Double, precision: Double, recall: Double, f1Score: Double, mae: Double, mse: Double, rmse: Double, mape: Double, directionalAccuracy: Double, sharpeRatio: Double?, maxDrawdown: Double?, hitRate: Double, confidence: Double, validationPeriod: TimeInterval, sampleSize: Int) {
        self.modelType = modelType
        self.timestamp = timestamp
        self.accuracy = accuracy
        self.precision = precision
        self.recall = recall
        self.f1Score = f1Score
        self.mae = mae
        self.mse = mse
        self.rmse = rmse
        self.mape = mape
        self.directionalAccuracy = directionalAccuracy
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.hitRate = hitRate
        self.confidence = confidence
        self.validationPeriod = validationPeriod
        self.sampleSize = sampleSize
    }
}

public struct ValidationModelMetrics {
    public let modelType: ModelType
    public let averageAccuracy: Double
    public let averagePrecision: Double
    public let averageRecall: Double
    public let averageF1Score: Double
    public let averageMAE: Double
    public let averageMSE: Double
    public let averageRMSE: Double
    public let averageMAPE: Double
    public let averageDirectionalAccuracy: Double
    public let averageHitRate: Double
    public let consistency: Double
    public let stability: Double
    public let totalValidations: Int
    public let validationPeriod: TimeInterval
    public let lastUpdated: Date

    public init(modelType: ModelType, averageAccuracy: Double, averagePrecision: Double, averageRecall: Double, averageF1Score: Double, averageMAE: Double, averageMSE: Double, averageRMSE: Double, averageMAPE: Double, averageDirectionalAccuracy: Double, averageHitRate: Double, consistency: Double, stability: Double, totalValidations: Int, validationPeriod: TimeInterval, lastUpdated: Date) {
        self.modelType = modelType
        self.averageAccuracy = averageAccuracy
        self.averagePrecision = averagePrecision
        self.averageRecall = averageRecall
        self.averageF1Score = averageF1Score
        self.averageMAE = averageMAE
        self.averageMSE = averageMSE
        self.averageRMSE = averageRMSE
        self.averageMAPE = averageMAPE
        self.averageDirectionalAccuracy = averageDirectionalAccuracy
        self.averageHitRate = averageHitRate
        self.consistency = consistency
        self.stability = stability
        self.totalValidations = totalValidations
        self.validationPeriod = validationPeriod
        self.lastUpdated = lastUpdated
    }
}

public struct BacktestResult {
    public let modelType: ModelType
    public let startDate: Date
    public let endDate: Date
    public let totalTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    public let winRate: Double
    public let averageWin: Double
    public let averageLoss: Double
    public let profitFactor: Double
    public let totalReturn: Double
    public let annualizedReturn: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let maxDrawdownDuration: TimeInterval
    public let calmarRatio: Double
    public let sortinoRatio: Double
    public let var95: Double // Value at Risk 95%
    public let cvar95: Double // Conditional Value at Risk 95%
    public let trades: [BacktestTrade]

    public init(modelType: ModelType, startDate: Date, endDate: Date, totalTrades: Int, winningTrades: Int, losingTrades: Int, winRate: Double, averageWin: Double, averageLoss: Double, profitFactor: Double, totalReturn: Double, annualizedReturn: Double, sharpeRatio: Double, maxDrawdown: Double, maxDrawdownDuration: TimeInterval, calmarRatio: Double, sortinoRatio: Double, var95: Double, cvar95: Double, trades: [BacktestTrade]) {
        self.modelType = modelType
        self.startDate = startDate
        self.endDate = endDate
        self.totalTrades = totalTrades
        self.winningTrades = winningTrades
        self.losingTrades = losingTrades
        self.winRate = winRate
        self.averageWin = averageWin
        self.averageLoss = averageLoss
        self.profitFactor = profitFactor
        self.totalReturn = totalReturn
        self.annualizedReturn = annualizedReturn
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.maxDrawdownDuration = maxDrawdownDuration
        self.calmarRatio = calmarRatio
        self.sortinoRatio = sortinoRatio
        self.var95 = var95
        self.cvar95 = cvar95
        self.trades = trades
    }
}

public struct BacktestTrade {
    public let entryDate: Date
    public let exitDate: Date
    public let entryPrice: Double
    public let exitPrice: Double
    public let quantity: Double
    public let pnl: Double
    public let pnlPercentage: Double
    public let duration: TimeInterval
    public let signal: String
    public let confidence: Double

    public init(entryDate: Date, exitDate: Date, entryPrice: Double, exitPrice: Double, quantity: Double, pnl: Double, pnlPercentage: Double, duration: TimeInterval, signal: String, confidence: Double) {
        self.entryDate = entryDate
        self.exitDate = exitDate
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.quantity = quantity
        self.pnl = pnl
        self.pnlPercentage = pnlPercentage
        self.duration = duration
        self.signal = signal
        self.confidence = confidence
    }
}

public struct WalkForwardResult {
    public let modelType: ModelType
    public let totalFolds: Int
    public let averageAccuracy: Double
    public let averageF1Score: Double
    public let averageMAPE: Double
    public let averageMAE: Double
    public let averageRMSE: Double
    public let consistency: Double
    public let stability: Double
    public let foldResults: [WalkForwardFold]
    public let timestamp: Date

    public init(modelType: ModelType, totalFolds: Int, averageAccuracy: Double, averageF1Score: Double, averageMAPE: Double, averageMAE: Double, averageRMSE: Double, consistency: Double, stability: Double, foldResults: [WalkForwardFold], timestamp: Date) {
        self.modelType = modelType
        self.totalFolds = totalFolds
        self.averageAccuracy = averageAccuracy
        self.averageF1Score = averageF1Score
        self.averageMAPE = averageMAPE
        self.averageMAE = averageMAE
        self.averageRMSE = averageRMSE
        self.consistency = consistency
        self.stability = stability
        self.foldResults = foldResults
        self.timestamp = timestamp
    }
}

public struct WalkForwardFold {
    public let foldNumber: Int
    public let trainingStart: Date
    public let trainingEnd: Date
    public let validationStart: Date
    public let validationEnd: Date
    public let accuracy: Double
    public let f1Score: Double
    public let mape: Double
    public let mae: Double
    public let rmse: Double
    public let sampleSize: Int

    public init(foldNumber: Int, trainingStart: Date, trainingEnd: Date, validationStart: Date, validationEnd: Date, accuracy: Double, f1Score: Double, mape: Double, mae: Double, rmse: Double, sampleSize: Int) {
        self.foldNumber = foldNumber
        self.trainingStart = trainingStart
        self.trainingEnd = trainingEnd
        self.validationStart = validationStart
        self.validationEnd = validationEnd
        self.accuracy = accuracy
        self.f1Score = f1Score
        self.mape = mape
        self.mae = mae
        self.rmse = rmse
        self.sampleSize = sampleSize
    }
}

public struct AccuracyTrackingResult {
    public let predictionId: String
    public let timestamp: Date
    public let actualValue: Double
    public let predictedValue: Double
    public let error: Double
    public let absoluteError: Double
    public let percentageError: Double
    public let isWithinTolerance: Bool
    public let tolerance: Double
    public let confidence: Double

    public init(predictionId: String, timestamp: Date, actualValue: Double, predictedValue: Double, error: Double, absoluteError: Double, percentageError: Double, isWithinTolerance: Bool, tolerance: Double, confidence: Double) {
        self.predictionId = predictionId
        self.timestamp = timestamp
        self.actualValue = actualValue
        self.predictedValue = predictedValue
        self.error = error
        self.absoluteError = absoluteError
        self.percentageError = percentageError
        self.isWithinTolerance = isWithinTolerance
        self.tolerance = tolerance
        self.confidence = confidence
    }
}

public class PredictionValidator: PredictionValidationProtocol {
    private let logger: StructuredLogger
    private let validationHistory: [ValidationResult] = []

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func validatePricePrediction(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        guard !actualData.isEmpty else {
            throw ValidationError.insufficientData
        }

        let actualPrices = actualData.map { $0.close }
        let predictedPrice = prediction.prediction

        // Calculate time-based validation
        let predictionTime = prediction.timestamp
        let validationData = actualData.filter { $0.timestamp >= predictionTime }

        guard !validationData.isEmpty else {
            throw ValidationError.noValidationData
        }

        // Calculate metrics
        let (mae, mse, rmse, mape) = calculatePriceMetrics(predicted: predictedPrice, actual: actualPrices)
        let directionalAccuracy = calculateDirectionalAccuracy(predicted: predictedPrice, actual: actualPrices)
        let hitRate = calculateHitRate(predicted: predictedPrice, actual: actualPrices, tolerance: 0.02) // 2% tolerance

        // Calculate Sharpe ratio and max drawdown for trading performance
        let returns = calculateReturns(prices: actualPrices)
        let sharpeRatio = calculateSharpeRatio(returns: returns)
        let maxDrawdown = calculateMaxDrawdown(prices: actualPrices)

        logger.info(component: "PredictionValidator", event: "Validated price prediction", data: [
            "modelType": ModelType.pricePrediction.rawValue,
            "mae": String(mae),
            "rmse": String(rmse),
            "directionalAccuracy": String(directionalAccuracy),
            "hitRate": String(hitRate)
        ])

        return ValidationResult(
            modelType: .pricePrediction,
            timestamp: Date(),
            accuracy: hitRate,
            precision: hitRate, // Simplified for price prediction
            recall: hitRate,
            f1Score: hitRate,
            mae: mae,
            mse: mse,
            rmse: rmse,
            mape: mape,
            directionalAccuracy: directionalAccuracy,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown,
            hitRate: hitRate,
            confidence: prediction.confidence,
            validationPeriod: validationData.last!.timestamp.timeIntervalSince(predictionTime),
            sampleSize: validationData.count
        )
    }

    public func validateVolatilityPrediction(prediction: VolatilityPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        guard !actualData.isEmpty else {
            throw ValidationError.insufficientData
        }

        let actualPrices = actualData.map { $0.close }
        let actualVolatility = calculateActualVolatility(prices: actualPrices)
        let predictedVolatility = prediction.predictedVolatility.first ?? 0.0

        // Calculate volatility metrics
        let (mae, mse, rmse, mape) = calculatePriceMetrics(predicted: predictedVolatility, actual: [actualVolatility])
        let hitRate = calculateHitRate(predicted: predictedVolatility, actual: [actualVolatility], tolerance: 0.1) // 10% tolerance for volatility

        logger.info(component: "PredictionValidator", event: "Validated volatility prediction", data: [
            "modelType": ModelType.volatilityPrediction.rawValue,
            "predictedVolatility": String(predictedVolatility),
            "actualVolatility": String(actualVolatility),
            "mae": String(mae),
            "hitRate": String(hitRate)
        ])

        return ValidationResult(
            modelType: .volatilityPrediction,
            timestamp: Date(),
            accuracy: hitRate,
            precision: hitRate,
            recall: hitRate,
            f1Score: hitRate,
            mae: mae,
            mse: mse,
            rmse: rmse,
            mape: mape,
            directionalAccuracy: hitRate,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: hitRate,
            confidence: prediction.confidence,
            validationPeriod: prediction.horizon,
            sampleSize: 1
        )
    }

    public func validateTrendClassification(classification: TrendClassification, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        guard actualData.count >= 2 else {
            throw ValidationError.insufficientData
        }

        let actualTrend = determineActualTrend(data: actualData)
        let predictedTrend = classification.trendType

        // Calculate classification metrics
        let isCorrect = actualTrend == predictedTrend
        let accuracy = isCorrect ? 1.0 : 0.0

        // Calculate trend strength accuracy
        let actualStrength = calculateActualTrendStrength(data: actualData)
        let strengthAccuracy = 1.0 - abs(actualStrength - classification.strength)

        logger.info(component: "PredictionValidator", event: "Validated trend classification", data: [
            "modelType": ModelType.trendClassification.rawValue,
            "predictedTrend": predictedTrend.rawValue,
            "actualTrend": actualTrend.rawValue,
            "isCorrect": String(isCorrect),
            "strengthAccuracy": String(strengthAccuracy)
        ])

        return ValidationResult(
            modelType: .trendClassification,
            timestamp: Date(),
            accuracy: accuracy,
            precision: accuracy,
            recall: accuracy,
            f1Score: accuracy,
            mae: 1.0 - strengthAccuracy,
            mse: pow(1.0 - strengthAccuracy, 2),
            rmse: 1.0 - strengthAccuracy,
            mape: (1.0 - strengthAccuracy) * 100,
            directionalAccuracy: accuracy,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: accuracy,
            confidence: classification.confidence,
            validationPeriod: classification.duration,
            sampleSize: actualData.count
        )
    }

    public func validateReversalPrediction(prediction: ReversalPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        guard actualData.count >= 10 else {
            throw ValidationError.insufficientData
        }

        let actualReversal = determineActualReversal(data: actualData)
        let predictedReversal = prediction.reversalType

        // Calculate reversal prediction accuracy
        let isCorrect = actualReversal == predictedReversal
        let accuracy = isCorrect ? 1.0 : 0.0

        // Calculate timing accuracy if reversal occurred
        let timingAccuracy = calculateTimingAccuracy(prediction: prediction, actualData: actualData)

        logger.info(component: "PredictionValidator", event: "Validated reversal prediction", data: [
            "modelType": ModelType.reversalPrediction.rawValue,
            "predictedReversal": predictedReversal.rawValue,
            "actualReversal": actualReversal.rawValue,
            "isCorrect": String(isCorrect),
            "timingAccuracy": String(timingAccuracy)
        ])

        return ValidationResult(
            modelType: .reversalPrediction,
            timestamp: Date(),
            accuracy: accuracy,
            precision: accuracy,
            recall: accuracy,
            f1Score: accuracy,
            mae: 1.0 - timingAccuracy,
            mse: pow(1.0 - timingAccuracy, 2),
            rmse: 1.0 - timingAccuracy,
            mape: (1.0 - timingAccuracy) * 100,
            directionalAccuracy: accuracy,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: accuracy,
            confidence: prediction.confidence,
            validationPeriod: actualData.last!.timestamp.timeIntervalSince(actualData.first!.timestamp),
            sampleSize: actualData.count
        )
    }

    public func calculateModelMetrics(predictions: [PredictionResponse], actualData: [MarketDataPoint]) async throws -> ValidationModelMetrics {
        guard !predictions.isEmpty else {
            throw ValidationError.insufficientData
        }

        var validationResults: [ValidationResult] = []

        for prediction in predictions {
            let result = try await validatePricePrediction(prediction: prediction, actualData: actualData)
            validationResults.append(result)
        }

        // Calculate average metrics
        let averageAccuracy = validationResults.map { $0.accuracy }.reduce(0, +) / Double(validationResults.count)
        let averagePrecision = validationResults.map { $0.precision }.reduce(0, +) / Double(validationResults.count)
        let averageRecall = validationResults.map { $0.recall }.reduce(0, +) / Double(validationResults.count)
        let averageF1Score = validationResults.map { $0.f1Score }.reduce(0, +) / Double(validationResults.count)
        let averageMAE = validationResults.map { $0.mae }.reduce(0, +) / Double(validationResults.count)
        let averageMSE = validationResults.map { $0.mse }.reduce(0, +) / Double(validationResults.count)
        let averageRMSE = validationResults.map { $0.rmse }.reduce(0, +) / Double(validationResults.count)
        let averageMAPE = validationResults.map { $0.mape }.reduce(0, +) / Double(validationResults.count)
        let averageDirectionalAccuracy = validationResults.map { $0.directionalAccuracy }.reduce(0, +) / Double(validationResults.count)
        let averageHitRate = validationResults.map { $0.hitRate }.reduce(0, +) / Double(validationResults.count)

        // Calculate consistency and stability
        let consistency = calculateConsistency(validationResults: validationResults)
        let stability = calculateStability(validationResults: validationResults)

        return ValidationModelMetrics(
            modelType: .pricePrediction,
            averageAccuracy: averageAccuracy,
            averagePrecision: averagePrecision,
            averageRecall: averageRecall,
            averageF1Score: averageF1Score,
            averageMAE: averageMAE,
            averageMSE: averageMSE,
            averageRMSE: averageRMSE,
            averageMAPE: averageMAPE,
            averageDirectionalAccuracy: averageDirectionalAccuracy,
            averageHitRate: averageHitRate,
            consistency: consistency,
            stability: stability,
            totalValidations: validationResults.count,
            validationPeriod: validationResults.last!.validationPeriod,
            lastUpdated: Date()
        )
    }

    public func performBacktesting(modelType: ModelType, historicalData: [MarketDataPoint], lookbackPeriod: TimeInterval) async throws -> BacktestResult {
        guard historicalData.count >= 100 else {
            throw ValidationError.insufficientData
        }

        let startDate = historicalData.first!.timestamp
        let endDate = historicalData.last!.timestamp

        // Simulate trading based on predictions
        var trades: [BacktestTrade] = []
        var currentPosition: BacktestTrade?
        var portfolioValue = 10000.0 // Starting with $10,000
        var maxPortfolioValue = portfolioValue
        var maxDrawdown = 0.0
        var maxDrawdownDuration: TimeInterval = 0
        var currentDrawdownDuration: TimeInterval = 0

        for i in 20..<historicalData.count {
            let currentData = Array(historicalData.prefix(i))
            let currentPrice = historicalData[i].close

            // Generate trading signal (simplified)
            let signal = generateTradingSignal(data: currentData, currentPrice: currentPrice)

            if let position = currentPosition {
                // Check exit conditions
                if shouldExitPosition(position: position, currentPrice: currentPrice, signal: signal) {
                    let exitTrade = BacktestTrade(
                        entryDate: position.entryDate,
                        exitDate: historicalData[i].timestamp,
                        entryPrice: position.entryPrice,
                        exitPrice: currentPrice,
                        quantity: position.quantity,
                        pnl: (currentPrice - position.entryPrice) * position.quantity,
                        pnlPercentage: (currentPrice - position.entryPrice) / position.entryPrice,
                        duration: historicalData[i].timestamp.timeIntervalSince(position.entryDate),
                        signal: signal,
                        confidence: 0.8
                    )

                    trades.append(exitTrade)
                    portfolioValue += exitTrade.pnl
                    currentPosition = nil
                }
            } else {
                // Check entry conditions
                if shouldEnterPosition(signal: signal, currentPrice: currentPrice) {
                    let quantity = portfolioValue * 0.1 / currentPrice // Risk 10% of portfolio
                    currentPosition = BacktestTrade(
                        entryDate: historicalData[i].timestamp,
                        exitDate: historicalData[i].timestamp,
                        entryPrice: currentPrice,
                        exitPrice: currentPrice,
                        quantity: quantity,
                        pnl: 0,
                        pnlPercentage: 0,
                        duration: 0,
                        signal: signal,
                        confidence: 0.8
                    )
                }
            }

            // Update drawdown tracking
            if portfolioValue > maxPortfolioValue {
                maxPortfolioValue = portfolioValue
                currentDrawdownDuration = 0
            } else {
                currentDrawdownDuration += historicalData[i].timestamp.timeIntervalSince(historicalData[i-1].timestamp)
                let currentDrawdown = (maxPortfolioValue - portfolioValue) / maxPortfolioValue
                if currentDrawdown > maxDrawdown {
                    maxDrawdown = currentDrawdown
                    maxDrawdownDuration = currentDrawdownDuration
                }
            }
        }

        // Close any remaining position
        if let position = currentPosition {
            let finalPrice = historicalData.last!.close
            let exitTrade = BacktestTrade(
                entryDate: position.entryDate,
                exitDate: historicalData.last!.timestamp,
                entryPrice: position.entryPrice,
                exitPrice: finalPrice,
                quantity: position.quantity,
                pnl: (finalPrice - position.entryPrice) * position.quantity,
                pnlPercentage: (finalPrice - position.entryPrice) / position.entryPrice,
                duration: historicalData.last!.timestamp.timeIntervalSince(position.entryDate),
                signal: "CLOSE",
                confidence: 0.8
            )
            trades.append(exitTrade)
        }

        // Calculate performance metrics
        let totalTrades = trades.count
        let winningTrades = trades.filter { $0.pnl > 0 }.count
        let losingTrades = trades.filter { $0.pnl < 0 }.count
        let winRate = totalTrades > 0 ? Double(winningTrades) / Double(totalTrades) : 0.0

        let averageWin = winningTrades > 0 ? trades.filter { $0.pnl > 0 }.map { $0.pnl }.reduce(0, +) / Double(winningTrades) : 0.0
        let averageLoss = losingTrades > 0 ? trades.filter { $0.pnl < 0 }.map { $0.pnl }.reduce(0, +) / Double(losingTrades) : 0.0
        let profitFactor = abs(averageLoss) > 0 ? (averageWin * Double(winningTrades)) / (abs(averageLoss) * Double(losingTrades)) : 0.0

        let totalReturn = (portfolioValue - 10000.0) / 10000.0
        let annualizedReturn = calculateAnnualizedReturn(totalReturn: totalReturn, period: endDate.timeIntervalSince(startDate))

        let returns = trades.map { $0.pnlPercentage }
        let sharpeRatio = calculateSharpeRatio(returns: returns)
        let calmarRatio = annualizedReturn / maxDrawdown
        let sortinoRatio = calculateSortinoRatio(returns: returns)

        let var95 = calculateVaR(returns: returns, confidence: 0.95)
        let cvar95 = calculateCVaR(returns: returns, confidence: 0.95)

        logger.info(component: "PredictionValidator", event: "Completed backtesting", data: [
            "modelType": modelType.rawValue,
            "totalTrades": String(totalTrades),
            "winRate": String(winRate),
            "totalReturn": String(totalReturn),
            "maxDrawdown": String(maxDrawdown)
        ])

        return BacktestResult(
            modelType: modelType,
            startDate: startDate,
            endDate: endDate,
            totalTrades: totalTrades,
            winningTrades: winningTrades,
            losingTrades: losingTrades,
            winRate: winRate,
            averageWin: averageWin,
            averageLoss: averageLoss,
            profitFactor: profitFactor,
            totalReturn: totalReturn,
            annualizedReturn: annualizedReturn,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown,
            maxDrawdownDuration: maxDrawdownDuration,
            calmarRatio: calmarRatio,
            sortinoRatio: sortinoRatio,
            var95: var95,
            cvar95: cvar95,
            trades: trades
        )
    }

    // MARK: - Private Methods

    private func calculatePriceMetrics(predicted: Double, actual: [Double]) -> (mae: Double, mse: Double, rmse: Double, mape: Double) {
        let errors = actual.map { abs($0 - predicted) }
        let squaredErrors = actual.map { pow($0 - predicted, 2) }
        let percentageErrors = actual.map { abs(($0 - predicted) / $0) * 100 }

        let mae = errors.reduce(0, +) / Double(errors.count)
        let mse = squaredErrors.reduce(0, +) / Double(squaredErrors.count)
        let rmse = sqrt(mse)
        let mape = percentageErrors.reduce(0, +) / Double(percentageErrors.count)

        return (mae, mse, rmse, mape)
    }

    private func calculateDirectionalAccuracy(predicted: Double, actual: [Double]) -> Double {
        guard actual.count >= 2 else { return 0.0 }

        let predictedDirection = predicted > actual[0] ? 1 : -1
        let actualDirection = actual[1] > actual[0] ? 1 : -1

        return predictedDirection == actualDirection ? 1.0 : 0.0
    }

    private func calculateHitRate(predicted: Double, actual: [Double], tolerance: Double) -> Double {
        let hits = actual.filter { abs($0 - predicted) / $0 <= tolerance }.count
        return Double(hits) / Double(actual.count)
    }

    private func calculateReturns(prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }

        var returns: [Double] = []
        for i in 1..<prices.count {
            let returnValue = (prices[i] - prices[i-1]) / prices[i-1]
            returns.append(returnValue)
        }
        return returns
    }

    private func calculateSharpeRatio(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0.0 }

        let meanReturn = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - meanReturn, 2) }.reduce(0, +) / Double(returns.count)
        let stdDev = sqrt(variance)

        return stdDev > 0 ? meanReturn / stdDev : 0.0
    }

    private func calculateMaxDrawdown(prices: [Double]) -> Double {
        guard !prices.isEmpty else { return 0.0 }

        var maxPrice = prices[0]
        var maxDrawdown = 0.0

        for price in prices {
            if price > maxPrice {
                maxPrice = price
            }
            let drawdown = (maxPrice - price) / maxPrice
            if drawdown > maxDrawdown {
                maxDrawdown = drawdown
            }
        }

        return maxDrawdown
    }

    private func calculateActualVolatility(prices: [Double]) -> Double {
        let returns = calculateReturns(prices: prices)
        guard !returns.isEmpty else { return 0.0 }

        let meanReturn = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - meanReturn, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance)
    }

    private func determineActualTrend(data: [MarketDataPoint]) -> TrendType {
        guard data.count >= 2 else { return .sideways }

        let prices = data.map { $0.close }
        let firstPrice = prices.first!
        let lastPrice = prices.last!
        let priceChange = (lastPrice - firstPrice) / firstPrice

        if priceChange > 0.05 {
            return .uptrend
        } else if priceChange < -0.05 {
            return .downtrend
        } else {
            return .sideways
        }
    }

    private func calculateActualTrendStrength(data: [MarketDataPoint]) -> Double {
        guard data.count >= 2 else { return 0.0 }

        let prices = data.map { $0.close }
        let priceChange = abs((prices.last! - prices.first!) / prices.first!)
        return min(priceChange * 10, 1.0) // Scale to 0-1 range
    }

    private func determineActualReversal(data: [MarketDataPoint]) -> ReversalType {
        guard data.count >= 10 else { return .noReversal }

        let prices = data.map { $0.close }
        let firstHalf = Array(prices.prefix(prices.count / 2))
        let secondHalf = Array(prices.suffix(prices.count / 2))

        let firstTrend = (firstHalf.last! - firstHalf.first!) / firstHalf.first!
        let secondTrend = (secondHalf.last! - secondHalf.first!) / secondHalf.first!

        if firstTrend > 0.02 && secondTrend < -0.02 {
            return .bearishReversal
        } else if firstTrend < -0.02 && secondTrend > 0.02 {
            return .bullishReversal
        } else {
            return .noReversal
        }
    }

    private func calculateTimingAccuracy(prediction: ReversalPrediction, actualData: [MarketDataPoint]) -> Double {
        // Simplified timing accuracy calculation
        return prediction.confidence
    }

    private func calculateConsistency(validationResults: [ValidationResult]) -> Double {
        guard validationResults.count > 1 else { return 1.0 }

        let accuracies = validationResults.map { $0.accuracy }
        let mean = accuracies.reduce(0, +) / Double(accuracies.count)
        let variance = accuracies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accuracies.count)
        let stdDev = sqrt(variance)

        return max(0, 1.0 - stdDev)
    }

    private func calculateStability(validationResults: [ValidationResult]) -> Double {
        guard validationResults.count > 1 else { return 1.0 }

        let accuracies = validationResults.map { $0.accuracy }
        let trend = calculateTrend(values: accuracies)

        return max(0, 1.0 - abs(trend))
    }

    private func calculateTrend(values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let n = Double(values.count)
        let x = Array(0..<values.count).map { Double($0) }
        let y = values

        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map { $0 * $1 }.reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        return slope
    }

    private func generateTradingSignal(data: [MarketDataPoint], currentPrice: Double) -> String {
        // Simplified trading signal generation
        guard data.count >= 20 else { return "HOLD" }

        let prices = data.map { $0.close }
        let sma20 = prices.suffix(20).reduce(0, +) / 20

        if currentPrice > sma20 * 1.02 {
            return "SELL"
        } else if currentPrice < sma20 * 0.98 {
            return "BUY"
        } else {
            return "HOLD"
        }
    }

    private func shouldEnterPosition(signal: String, currentPrice: Double) -> Bool {
        return signal == "BUY"
    }

    private func shouldExitPosition(position: BacktestTrade, currentPrice: Double, signal: String) -> Bool {
        return signal == "SELL" ||
               (currentPrice - position.entryPrice) / position.entryPrice > 0.05 || // 5% profit target
               (currentPrice - position.entryPrice) / position.entryPrice < -0.03 // 3% stop loss
    }

    private func calculateAnnualizedReturn(totalReturn: Double, period: TimeInterval) -> Double {
        let years = period / (365 * 24 * 60 * 60) // Convert to years
        return years > 0 ? pow(1 + totalReturn, 1 / years) - 1 : 0.0
    }

    private func calculateSortinoRatio(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0.0 }

        let meanReturn = returns.reduce(0, +) / Double(returns.count)
        let downsideReturns = returns.filter { $0 < 0 }
        let downsideVariance = downsideReturns.map { pow($0, 2) }.reduce(0, +) / Double(returns.count)
        let downsideStdDev = sqrt(downsideVariance)

        return downsideStdDev > 0 ? meanReturn / downsideStdDev : 0.0
    }

    private func calculateVaR(returns: [Double], confidence: Double) -> Double {
        guard !returns.isEmpty else { return 0.0 }

        let sortedReturns = returns.sorted()
        let index = Int((1 - confidence) * Double(sortedReturns.count))
        return sortedReturns[min(index, sortedReturns.count - 1)]
    }

    private func calculateCVaR(returns: [Double], confidence: Double) -> Double {
        guard !returns.isEmpty else { return 0.0 }

        let var95 = calculateVaR(returns: returns, confidence: confidence)
        let tailReturns = returns.filter { $0 <= var95 }

        return tailReturns.isEmpty ? var95 : tailReturns.reduce(0, +) / Double(tailReturns.count)
    }

    // MARK: - Walk-Forward Validation

    public func performWalkForwardValidation(modelType: ModelType, historicalData: [MarketDataPoint], trainingWindow: TimeInterval, validationWindow: TimeInterval, stepSize: TimeInterval) async throws -> WalkForwardResult {
        guard historicalData.count >= 100 else {
            throw ValidationError.insufficientData
        }

        let startDate = historicalData.first!.timestamp
        let endDate = historicalData.last!.timestamp

        var foldResults: [WalkForwardFold] = []
        var foldNumber = 1

        var currentStart = startDate

        while currentStart.addingTimeInterval(trainingWindow + validationWindow) <= endDate {
            let trainingEnd = currentStart.addingTimeInterval(trainingWindow)
            let validationEnd = trainingEnd.addingTimeInterval(validationWindow)

            // Get training and validation data
            let trainingData = historicalData.filter { $0.timestamp >= currentStart && $0.timestamp < trainingEnd }
            let validationData = historicalData.filter { $0.timestamp >= trainingEnd && $0.timestamp < validationEnd }

            guard !trainingData.isEmpty && !validationData.isEmpty else {
                currentStart = currentStart.addingTimeInterval(stepSize)
                continue
            }

            // Perform validation for this fold
            let foldResult = try await validateFold(
                foldNumber: foldNumber,
                trainingData: trainingData,
                validationData: validationData,
                modelType: modelType
            )

            foldResults.append(foldResult)
            foldNumber += 1
            currentStart = currentStart.addingTimeInterval(stepSize)
        }

        guard !foldResults.isEmpty else {
            throw ValidationError.insufficientData
        }

        // Calculate aggregate metrics
        let averageAccuracy = foldResults.map { $0.accuracy }.reduce(0, +) / Double(foldResults.count)
        let averageF1Score = foldResults.map { $0.f1Score }.reduce(0, +) / Double(foldResults.count)
        let averageMAPE = foldResults.map { $0.mape }.reduce(0, +) / Double(foldResults.count)
        let averageMAE = foldResults.map { $0.mae }.reduce(0, +) / Double(foldResults.count)
        let averageRMSE = foldResults.map { $0.rmse }.reduce(0, +) / Double(foldResults.count)

        // Calculate consistency and stability
        let accuracies = foldResults.map { $0.accuracy }
        let consistency = calculateConsistencyFromAccuracies(accuracies)
        let stability = calculateStabilityFromAccuracies(accuracies)

        logger.info(component: "PredictionValidator", event: "Walk-forward validation completed", data: [
            "modelType": modelType.rawValue,
            "totalFolds": String(foldResults.count),
            "averageAccuracy": String(averageAccuracy),
            "averageF1Score": String(averageF1Score),
            "averageMAPE": String(averageMAPE)
        ])

        return WalkForwardResult(
            modelType: modelType,
            totalFolds: foldResults.count,
            averageAccuracy: averageAccuracy,
            averageF1Score: averageF1Score,
            averageMAPE: averageMAPE,
            averageMAE: averageMAE,
            averageRMSE: averageRMSE,
            consistency: consistency,
            stability: stability,
            foldResults: foldResults,
            timestamp: Date()
        )
    }

    private func validateFold(foldNumber: Int, trainingData: [MarketDataPoint], validationData: [MarketDataPoint], modelType: ModelType) async throws -> WalkForwardFold {
        // Simulate model training and prediction for this fold
        let trainingPrices = trainingData.map { $0.close }
        let validationPrices = validationData.map { $0.close }

        // Simple baseline prediction (in production, this would use actual ML models)
        let avgTrainingPrice = trainingPrices.reduce(0, +) / Double(trainingPrices.count)
        _ = validationPrices.map { _ in avgTrainingPrice }

        // Calculate metrics
        let (mae, _, rmse, mape) = calculatePriceMetrics(predicted: avgTrainingPrice, actual: validationPrices)
        let accuracy = calculateHitRate(predicted: avgTrainingPrice, actual: validationPrices, tolerance: 0.02)
        let f1Score = accuracy // Simplified for price prediction

        return WalkForwardFold(
            foldNumber: foldNumber,
            trainingStart: trainingData.first!.timestamp,
            trainingEnd: trainingData.last!.timestamp,
            validationStart: validationData.first!.timestamp,
            validationEnd: validationData.last!.timestamp,
            accuracy: accuracy,
            f1Score: f1Score,
            mape: mape,
            mae: mae,
            rmse: rmse,
            sampleSize: validationData.count
        )
    }

    // MARK: - Accuracy Tracking

    public func trackPredictionAccuracy(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> AccuracyTrackingResult {
        guard !actualData.isEmpty else {
            throw ValidationError.insufficientData
        }

        let predictionId = UUID().uuidString
        let actualValue = actualData.last!.close
        let predictedValue = prediction.prediction

        let error = predictedValue - actualValue
        let absoluteError = abs(error)
        let percentageError = (error / actualValue) * 100

        let tolerance = 0.02 // 2% tolerance
        let isWithinTolerance = percentageError <= tolerance * 100

        logger.debug(component: "PredictionValidator", event: "Tracked prediction accuracy", data: [
            "predictionId": predictionId,
            "predictedValue": String(predictedValue),
            "actualValue": String(actualValue),
            "percentageError": String(percentageError),
            "isWithinTolerance": String(isWithinTolerance)
        ])

        return AccuracyTrackingResult(
            predictionId: predictionId,
            timestamp: Date(),
            actualValue: actualValue,
            predictedValue: predictedValue,
            error: error,
            absoluteError: absoluteError,
            percentageError: percentageError,
            isWithinTolerance: isWithinTolerance,
            tolerance: tolerance,
            confidence: prediction.confidence
        )
    }

    private func calculateConsistencyFromAccuracies(_ accuracies: [Double]) -> Double {
        guard accuracies.count > 1 else { return 1.0 }

        let mean = accuracies.reduce(0, +) / Double(accuracies.count)
        let variance = accuracies.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accuracies.count)
        let stdDev = sqrt(variance)

        return max(0, 1.0 - stdDev)
    }

    private func calculateStabilityFromAccuracies(_ accuracies: [Double]) -> Double {
        guard accuracies.count > 1 else { return 1.0 }

        let trend = calculateTrend(values: accuracies)
        return max(0, 1.0 - abs(trend))
    }
}

public enum ValidationError: Error {
    case insufficientData
    case noValidationData
    case calculationFailed
    case invalidParameters
}
