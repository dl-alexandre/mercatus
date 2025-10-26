import Foundation

public struct MarketDataPoint: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let symbol: String
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public let exchange: String

    public init(timestamp: Date, symbol: String, open: Double, high: Double, low: Double, close: Double, volume: Double, exchange: String) {
        self.timestamp = timestamp
        self.symbol = symbol
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.exchange = exchange
    }
}

public struct FeatureSet: Codable, Equatable {
    public let timestamp: Date
    public let symbol: String
    public let features: [String: Double]
    public let qualityScore: Double

    public init(timestamp: Date, symbol: String, features: [String: Double], qualityScore: Double) {
        self.timestamp = timestamp
        self.symbol = symbol
        self.features = features
        self.qualityScore = qualityScore
    }
}

public struct TradingSignal: Codable, Equatable {
    public let timestamp: Date
    public let symbol: String
    public let signalType: SignalType
    public let confidence: Double
    public let priceTarget: Double?
    public let stopLoss: Double?
    public let timeHorizon: TimeInterval

    public enum SignalType: String, Codable, CaseIterable {
        case buy = "BUY"
        case sell = "SELL"
        case hold = "HOLD"
        case strongBuy = "STRONG_BUY"
        case strongSell = "STRONG_SELL"
    }

    public init(timestamp: Date, symbol: String, signalType: SignalType, confidence: Double, priceTarget: Double? = nil, stopLoss: Double? = nil, timeHorizon: TimeInterval) {
        self.timestamp = timestamp
        self.symbol = symbol
        self.signalType = signalType
        self.confidence = confidence
        self.priceTarget = priceTarget
        self.stopLoss = stopLoss
        self.timeHorizon = timeHorizon
    }
}

public struct ModelInfo: Codable, Equatable {
    public let modelId: String
    public let version: String
    public let modelType: ModelType
    public let trainingDataHash: String
    public let accuracy: Double
    public let createdAt: Date
    public let isActive: Bool

    public enum ModelType: String, Codable, CaseIterable, Sendable {
        case pricePrediction = "PRICE_PREDICTION"
        case volatilityPrediction = "VOLATILITY_PREDICTION"
        case trendClassification = "TREND_CLASSIFICATION"
        case patternRecognition = "PATTERN_RECOGNITION"
    }

    public init(modelId: String, version: String, modelType: ModelType, trainingDataHash: String, accuracy: Double, createdAt: Date, isActive: Bool) {
        self.modelId = modelId
        self.version = version
        self.modelType = modelType
        self.trainingDataHash = trainingDataHash
        self.accuracy = accuracy
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

public struct DetectedPattern: Codable, Equatable {
    public let patternId: String
    public let patternType: PatternType
    public let symbol: String
    public let startTime: Date
    public let endTime: Date
    public let confidence: Double
    public let completionScore: Double
    public let priceTarget: Double?
    public let stopLoss: Double?
    public let marketConditions: [String: String]

    public enum PatternType: String, Codable, CaseIterable {
        case headAndShoulders = "HEAD_AND_SHOULDERS"
        case triangle = "TRIANGLE"
        case flag = "FLAG"
        case supportResistance = "SUPPORT_RESISTANCE"
        case trendChannel = "TREND_CHANNEL"
        case doubleTop = "DOUBLE_TOP"
        case doubleBottom = "DOUBLE_BOTTOM"
    }

    public init(patternId: String, patternType: PatternType, symbol: String, startTime: Date, endTime: Date, confidence: Double, completionScore: Double, priceTarget: Double? = nil, stopLoss: Double? = nil, marketConditions: [String: String] = [:]) {
        self.patternId = patternId
        self.patternType = patternType
        self.symbol = symbol
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.completionScore = completionScore
        self.priceTarget = priceTarget
        self.stopLoss = stopLoss
        self.marketConditions = marketConditions
    }
}

public struct PredictionRequest: Codable, Equatable {
    public let symbol: String
    public let timeHorizon: TimeInterval
    public let features: [String: Double]
    public let modelType: ModelInfo.ModelType

    public init(symbol: String, timeHorizon: TimeInterval, features: [String: Double], modelType: ModelInfo.ModelType) {
        self.symbol = symbol
        self.timeHorizon = timeHorizon
        self.features = features
        self.modelType = modelType
    }
}

public struct PredictionResponse: Codable, Equatable, Sendable {
    public let id: String
    public let prediction: Double
    public let confidence: Double
    public let uncertainty: Double
    public let modelVersion: String
    public let timestamp: Date

    public init(id: String, prediction: Double, confidence: Double, uncertainty: Double, modelVersion: String, timestamp: Date) {
        self.id = id
        self.prediction = prediction
        self.confidence = confidence
        self.uncertainty = uncertainty
        self.modelVersion = modelVersion
        self.timestamp = timestamp
    }
}

public struct VolatilityAlert: Codable, Equatable, Sendable {
    public let symbol: String
    public let horizon: TimeInterval
    public let volatility: Double
    public let threshold: Double
    public let severity: String
    public let message: String
    public let timestamp: Date

    public init(symbol: String, horizon: TimeInterval, volatility: Double, threshold: Double, severity: String, message: String) {
        self.symbol = symbol
        self.horizon = horizon
        self.volatility = volatility
        self.threshold = threshold
        self.severity = severity
        self.message = message
        self.timestamp = Date()
    }
}
