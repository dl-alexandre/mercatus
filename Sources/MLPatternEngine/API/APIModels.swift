import Foundation

// MARK: - Request Models

public struct PredictionRequestDTO: Codable, Sendable {
    public let symbol: String
    public let timeHorizon: TimeInterval
    public let modelType: String
    public let features: [String: Double]

    public init(symbol: String, timeHorizon: TimeInterval, modelType: String, features: [String: Double]) {
        self.symbol = symbol
        self.timeHorizon = timeHorizon
        self.modelType = modelType
        self.features = features
    }
}

public struct PatternDetectionRequestDTO: Codable {
    public let symbol: String
    public let patternTypes: [String]?
    public let timeRange: TimeRangeDTO?

    public init(symbol: String, patternTypes: [String]? = nil, timeRange: TimeRangeDTO? = nil) {
        self.symbol = symbol
        self.patternTypes = patternTypes
        self.timeRange = timeRange
    }
}

public struct TimeRangeDTO: Codable {
    public let from: Date
    public let to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }
}

public struct BatchPredictionRequestDTO: Codable {
    public let requests: [PredictionRequestDTO]

    public init(requests: [PredictionRequestDTO]) {
        self.requests = requests
    }
}

// MARK: - Response Models

public struct PredictionResponseDTO: Codable, Sendable {
    public let prediction: Double
    public let confidence: Double
    public let uncertainty: Double
    public let modelVersion: String
    public let timestamp: Date
    public let symbol: String
    public let timeHorizon: TimeInterval

    public init(prediction: Double, confidence: Double, uncertainty: Double, modelVersion: String, timestamp: Date, symbol: String, timeHorizon: TimeInterval) {
        self.prediction = prediction
        self.confidence = confidence
        self.uncertainty = uncertainty
        self.modelVersion = modelVersion
        self.timestamp = timestamp
        self.symbol = symbol
        self.timeHorizon = timeHorizon
    }
}

public struct PatternResponseDTO: Codable {
    public let patternId: String
    public let patternType: String
    public let symbol: String
    public let startTime: Date
    public let endTime: Date
    public let confidence: Double
    public let completionScore: Double
    public let priceTarget: Double?
    public let stopLoss: Double?
    public let marketConditions: [String: String]

    public init(patternId: String, patternType: String, symbol: String, startTime: Date, endTime: Date, confidence: Double, completionScore: Double, priceTarget: Double? = nil, stopLoss: Double? = nil, marketConditions: [String: String] = [:]) {
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

public struct HealthResponseDTO: Codable {
    public let isHealthy: Bool
    public let latency: TimeInterval
    public let cacheHitRate: Double
    public let activeModels: [String]
    public let lastUpdated: Date
    public let version: String

    public init(isHealthy: Bool, latency: TimeInterval, cacheHitRate: Double, activeModels: [String], lastUpdated: Date, version: String) {
        self.isHealthy = isHealthy
        self.latency = latency
        self.cacheHitRate = cacheHitRate
        self.activeModels = activeModels
        self.lastUpdated = lastUpdated
        self.version = version
    }
}

public struct ModelInfoResponseDTO: Codable {
    public let modelId: String
    public let version: String
    public let modelType: String
    public let accuracy: Double
    public let createdAt: Date
    public let isActive: Bool

    public init(modelId: String, version: String, modelType: String, accuracy: Double, createdAt: Date, isActive: Bool) {
        self.modelId = modelId
        self.version = version
        self.modelType = modelType
        self.accuracy = accuracy
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

// MARK: - Error Models

public struct APIErrorDTO: Codable {
    public let error: String
    public let code: String
    public let message: String
    public let timestamp: Date
    public let requestId: String?

    public init(error: String, code: String, message: String, timestamp: Date, requestId: String? = nil) {
        self.error = error
        self.code = code
        self.message = message
        self.timestamp = timestamp
        self.requestId = requestId
    }
}

// MARK: - Error Codes

public enum APIErrorCode: String, CaseIterable {
    case modelNotReady = "MODEL_NOT_READY"
    case dataInsufficient = "DATA_INSUFFICIENT"
    case invalidPair = "INVALID_PAIR"
    case staleModel = "STALE_MODEL"
    case invalidRequest = "INVALID_REQUEST"
    case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
    case internalError = "INTERNAL_ERROR"
    case unauthorized = "UNAUTHORIZED"
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
}

// MARK: - Authentication

public struct AuthTokenDTO: Codable {
    public let token: String
    public let expiresAt: Date
    public let permissions: [String]

    public init(token: String, expiresAt: Date, permissions: [String]) {
        self.token = token
        self.expiresAt = expiresAt
        self.permissions = permissions
    }
}

public struct LoginRequestDTO: Codable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

// MARK: - API Errors

public enum APIError: Error, Equatable {
    case invalidRequest
    case invalidModelType(String)
    case unauthorized
    case forbidden
    case rateLimitExceeded
    case invalidInput
    case internalError
    case serviceUnavailable
}
