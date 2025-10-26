import Foundation
import Utils
import MLPatternEngine

public class APIService: @unchecked Sendable {
    private let mlEngine: MLPatternEngine
    private let logger: StructuredLogger
    private let securityMiddleware: SecurityMiddlewareProtocol
    private let rateLimiter: RateLimiter
    private let authManager: AuthManager

    public init(mlEngine: MLPatternEngine, logger: StructuredLogger, securityMiddleware: SecurityMiddlewareProtocol, rateLimiter: RateLimiter, authManager: AuthManager) {
        self.mlEngine = mlEngine
        self.logger = logger
        self.securityMiddleware = securityMiddleware
        self.rateLimiter = rateLimiter
        self.authManager = authManager
    }

    // MARK: - Prediction Endpoints

    public func predictPrice(request: PredictionRequestDTO, authToken: String?) async throws -> PredictionResponseDTO {
        let apiRequest = try createAPIRequest(from: request, authToken: authToken)

        let authResult = try await securityMiddleware.authenticate(request: apiRequest)
        guard authResult.isAuthenticated, let user = authResult.user else {
            throw APIError.unauthorized
        }

        guard try await securityMiddleware.authorize(request: apiRequest, user: user) else {
            throw APIError.forbidden
        }

        guard try await securityMiddleware.validateRateLimit(request: apiRequest) else {
            throw APIError.rateLimitExceeded
        }

        guard try await securityMiddleware.validateInput(request: apiRequest) else {
            throw APIError.invalidInput
        }

        let modelType = try parseModelType(request.modelType)
        let prediction: PredictionResponse
        do {
            prediction = try await mlEngine.getPrediction(
                for: request.symbol,
                timeHorizon: request.timeHorizon,
                modelType: modelType
            )
        } catch {
            logger.error(component: "APIService", event: "ML Engine prediction failed", data: [
                "symbol": request.symbol,
                "error": error.localizedDescription
            ])
            throw APIError.internalError
        }

        return PredictionResponseDTO(
            prediction: prediction.prediction,
            confidence: prediction.confidence,
            uncertainty: prediction.uncertainty,
            modelVersion: prediction.modelVersion,
            timestamp: prediction.timestamp,
            symbol: request.symbol,
            timeHorizon: request.timeHorizon
        )
    }

    public func detectPatterns(request: PatternDetectionRequestDTO, authToken: String?) async throws -> [PatternResponseDTO] {
        try await validateAuth(authToken)
        _ = try await rateLimiter.checkLimit(for: authToken ?? "anonymous")

        let patterns = try await mlEngine.detectPatterns(for: request.symbol)

        var filteredPatterns = patterns
        if let patternTypes = request.patternTypes {
            filteredPatterns = patterns.filter { pattern in
                patternTypes.contains(pattern.patternType.rawValue)
            }
        }

        return filteredPatterns.map { pattern in
            PatternResponseDTO(
                patternId: pattern.patternId,
                patternType: pattern.patternType.rawValue,
                symbol: pattern.symbol,
                startTime: pattern.startTime,
                endTime: pattern.endTime,
                confidence: pattern.confidence,
                completionScore: pattern.completionScore,
                priceTarget: pattern.priceTarget,
                stopLoss: pattern.stopLoss,
                marketConditions: pattern.marketConditions
            )
        }
    }

    public func batchPredict(request: BatchPredictionRequestDTO, authToken: String?) async throws -> [PredictionResponseDTO] {
        try await validateAuth(authToken)
        _ = try await rateLimiter.checkLimit(for: authToken ?? "anonymous")

        var responses: [PredictionResponseDTO] = []

        for predictionRequest in request.requests {
            do {
                let modelType = try parseModelType(predictionRequest.modelType)
                let prediction = try await mlEngine.getPrediction(
                    for: predictionRequest.symbol,
                    timeHorizon: predictionRequest.timeHorizon,
                    modelType: modelType
                )

                let response = PredictionResponseDTO(
                    prediction: prediction.prediction,
                    confidence: prediction.confidence,
                    uncertainty: prediction.uncertainty,
                    modelVersion: prediction.modelVersion,
                    timestamp: prediction.timestamp,
                    symbol: predictionRequest.symbol,
                    timeHorizon: predictionRequest.timeHorizon
                )
                responses.append(response)
            } catch {
                logger.error(component: "APIService", event: "Failed to predict for \(predictionRequest.symbol): \(error)")
            }
        }

        return responses
    }

    // MARK: - Health and Status Endpoints

    public func getHealth() -> HealthResponseDTO {
        let health = mlEngine.getServiceHealth()
        return HealthResponseDTO(
            isHealthy: health.isHealthy,
            latency: health.latency,
            cacheHitRate: health.cacheHitRate,
            activeModels: health.activeModels,
            lastUpdated: health.lastUpdated,
            version: "1.0.0"
        )
    }

    public func getModels(authToken: String?) async throws -> [ModelInfoResponseDTO] {
        try await validateAuth(authToken)

        // In a real implementation, this would query the model manager
        return [
            ModelInfoResponseDTO(
                modelId: "price-prediction-v1",
                version: "1.0.0",
                modelType: "PRICE_PREDICTION",
                accuracy: 0.87,
                createdAt: Date().addingTimeInterval(-86400),
                isActive: true
            ),
            ModelInfoResponseDTO(
                modelId: "volatility-prediction-v1",
                version: "1.0.0",
                modelType: "VOLATILITY_PREDICTION",
                accuracy: 0.82,
                createdAt: Date().addingTimeInterval(-86400),
                isActive: true
            )
        ]
    }

    // MARK: - Authentication Endpoints

    public func login(request: LoginRequestDTO) async throws -> AuthTokenDTO {
        // In a real implementation, this would validate credentials
        let token = authManager.generateToken(for: request.username)
        return AuthTokenDTO(
            token: token,
            expiresAt: Date().addingTimeInterval(3600), // 1 hour
            permissions: ["predict", "patterns", "health"]
        )
    }

    // MARK: - Private Helpers

    private func parseModelType(_ modelTypeString: String) throws -> ModelInfo.ModelType {
        guard let modelType = ModelInfo.ModelType(rawValue: modelTypeString.uppercased()) else {
            throw APIError.invalidModelType(modelTypeString)
        }
        return modelType
    }

    private func createAPIRequest(from request: PredictionRequestDTO, authToken: String?) throws -> APIRequest {
        // Validate the request data before encoding
        try validateRequestData(request)

        let headers = [
        "Authorization": authToken != nil ? "Bearer \(authToken!)" : "",
        "Content-Type": "application/json"
        ]

        let body = try JSONEncoder().encode(request)

        return APIRequest(
            path: "/api/v1/predict",
            method: "POST",
            headers: headers,
            queryParams: [:],
            body: body,
            clientIP: "127.0.0.1", // Would be extracted from request context
            userAgent: "Mercatus-Client/1.0",
            timestamp: Date()
        )
    }

    private func validateRequestData(_ request: PredictionRequestDTO) throws {
        // Check for NaN or Infinity values in features
        for (_, value) in request.features {
            if value.isNaN || value.isInfinite {
                throw APIError.invalidInput
            }
            // Check for negative prices (assuming price is a key feature)
            if value < 0 {
                throw APIError.invalidInput
            }
        }

        // Check for other invalid values
        if request.timeHorizon <= 0 {
            throw APIError.invalidInput
        }

        if request.symbol.isEmpty {
            throw APIError.invalidInput
        }
    }

    private func validateAuth(_ authToken: String?) async throws {
        guard let token = authToken else {
            throw APIError.unauthorized
        }

        // This would use the security middleware in a real implementation
        guard !token.isEmpty else {
            throw APIError.unauthorized
        }
    }
}
