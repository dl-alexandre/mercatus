import Testing
import Foundation
@testable import MLPatternEngine
@testable import MLPatternEngineAPI
@testable import Utils

@Suite("End-to-End Workflow Tests")
struct EndToEndTests {

    @Test func testCompletePredictionWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        // Step 1: Authenticate user
        let authToken = "valid-token"

        // Step 2: Make prediction request
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: [
                "price": 50000.0,
                "volatility": 0.02,
                "trend_strength": 0.1,
                "rsi": 50.0,
                "macd": 0.0
            ]
        )

        let response = try await apiService.predictPrice(
            request: request,
            authToken: authToken
        )

        // Step 3: Verify response
        #expect(response.symbol == "BTC-USD")
        #expect(response.timeHorizon == 300)
        #expect(response.prediction > 0)
        #expect(response.confidence >= 0.0 && response.confidence <= 1.0)
        #expect(response.uncertainty >= 0.0 && response.uncertainty <= 1.0)
        #expect(!response.modelVersion.isEmpty)

        // Step 4: Verify model version is consistent
        let modelInfo = try await apiService.getModels(authToken: authToken)
        #expect(modelInfo.contains { $0.modelId.contains("price-prediction") })
    }

    @Test func testPatternDetectionWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        // Step 1: Authenticate user
        let authToken = "valid-token"

        // Step 2: Detect patterns
        let request = PatternDetectionRequestDTO(
            symbol: "ETH-USD",
            patternTypes: ["head_and_shoulders", "double_top", "triangle"],
            timeRange: TimeRangeDTO(
                from: Date().addingTimeInterval(-86400), // 24 hours ago
                to: Date()
            )
        )

        let patterns = try await apiService.detectPatterns(
            request: request,
            authToken: authToken
        )

        // Step 3: Verify patterns
        #expect(patterns.count >= 0)
        for pattern in patterns {
            #expect(!pattern.patternId.isEmpty)
            #expect(!pattern.patternType.isEmpty)
            #expect(pattern.symbol == "ETH-USD")
            #expect(pattern.confidence >= 0.0 && pattern.confidence <= 1.0)
            #expect(pattern.completionScore >= 0.0 && pattern.completionScore <= 1.0)
        }
    }

    @Test func testBatchPredictionWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        // Step 1: Authenticate user
        let authToken = "valid-token"

        // Step 2: Create batch prediction requests
        let requests = [
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": 50000.0, "volatility": 0.02]
            ),
            PredictionRequestDTO(
                symbol: "ETH-USD",
                timeHorizon: 600,
                modelType: "VOLATILITY_PREDICTION",
                features: ["price": 3000.0, "volatility": 0.03]
            ),
            PredictionRequestDTO(
                symbol: "SOL-USD",
                timeHorizon: 900,
                modelType: "TREND_CLASSIFICATION",
                features: ["price": 100.0, "trend_strength": 0.2]
            )
        ]

        // Step 3: Execute batch predictions
        let responses = try await apiService.batchPredict(
            request: BatchPredictionRequestDTO(requests: requests),
            authToken: authToken
        )

        // Step 4: Verify responses
        #expect(responses.count == 3)
        #expect(responses[0].symbol == "BTC-USD")
        #expect(responses[1].symbol == "ETH-USD")
        #expect(responses[2].symbol == "SOL-USD")

        for response in responses {
            #expect(response.prediction > 0)
            #expect(response.confidence >= 0.0 && response.confidence <= 1.0)
        }
    }

    @Test func testErrorHandlingWorkflow() async throws {
        let logger = createTestLogger()
        let failingMLEngine = createFailingMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: failingMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        // Step 1: Test authentication error
        await #expect(throws: APIError.unauthorized) {
            try await apiService.predictPrice(
                request: PredictionRequestDTO(
                    symbol: "BTC-USD",
                    timeHorizon: 300,
                    modelType: "PRICE_PREDICTION",
                    features: ["price": 50000.0]
                ),
                authToken: nil as String?
            )
        }

        // Step 2: Test invalid token
        await #expect(throws: APIError.unauthorized) {
            try await apiService.predictPrice(
                request: PredictionRequestDTO(
                    symbol: "BTC-USD",
                    timeHorizon: 300,
                    modelType: "PRICE_PREDICTION",
                    features: ["price": 50000.0]
                ),
                authToken: "invalid-token"
            )
        }

        // Step 3: Test ML engine error
        await #expect(throws: APIError.internalError) {
            try await apiService.predictPrice(
                request: PredictionRequestDTO(
                    symbol: "BTC-USD",
                    timeHorizon: 300,
                    modelType: "PRICE_PREDICTION",
                    features: ["price": 50000.0]
                ),
                authToken: "valid-token"
            )
        }
    }

    @Test func testPerformanceWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        // Measure response time
        let startTime = Date()
        let response = try await apiService.predictPrice(
            request: request,
            authToken: authToken
        )
        let responseTime = Date().timeIntervalSince(startTime)

        // Verify response time is within acceptable limits
        #expect(responseTime < 1.0) // Should respond within 1 second
        #expect(response.symbol == "BTC-USD")
    }

    @Test func testConcurrentRequestsWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let symbols = ["BTC-USD", "ETH-USD", "SOL-USD", "AVAX-USD", "ADA-USD"]

        // Create concurrent requests
        let tasks = symbols.map { symbol in
            Task {
                let request = PredictionRequestDTO(
                    symbol: symbol,
                    timeHorizon: 300,
                    modelType: "PRICE_PREDICTION",
                    features: ["price": 50000.0]
                )
                return try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
            }
        }

        // Wait for all requests to complete
        let responses = try await withThrowingTaskGroup(of: PredictionResponseDTO.self) { group in
            for task in tasks {
                group.addTask {
                    try await task.value
                }
            }

            var results: [PredictionResponseDTO] = []
            for try await response in group {
                results.append(response)
            }
            return results
        }

        // Verify all responses
        #expect(responses.count == symbols.count)

        let responseSymbols = responses.map { $0.symbol }
        for symbol in symbols {
            #expect(responseSymbols.contains(symbol))
        }

        for response in responses {
            #expect(response.prediction > 0)
        }
    }

    @Test func testHealthCheckWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        // Test health endpoint
        let health = apiService.getHealth()

        #expect(health.isHealthy == true)
        #expect(health.latency >= 0)
        #expect(health.cacheHitRate >= 0.0 && health.cacheHitRate <= 1.0)
        #expect(health.activeModels.count >= 0)
        #expect(!health.version.isEmpty)
    }

    @Test func testModelManagementWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"

        // Get models
        let models = try await apiService.getModels(authToken: authToken)

        #expect(models.count >= 0)
        for model in models {
            #expect(!model.modelId.isEmpty)
            #expect(!model.version.isEmpty)
            #expect(!model.modelType.isEmpty)
            #expect(model.accuracy >= 0.0 && model.accuracy <= 1.0)
        }
    }

    @Test func testDataValidationWorkflow() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = EndToEndMockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"

        // Test valid request
        let validRequest = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        let validResponse = try await apiService.predictPrice(
            request: validRequest,
            authToken: authToken
        )
        #expect(validResponse.symbol == "BTC-USD")

        // Test invalid model type
        let invalidRequest = PredictionRequestDTO(
        symbol: "BTC-USD",
        timeHorizon: 300,
        modelType: "INVALID_TYPE",
        features: [:]
        )

        await #expect(throws: APIError.invalidModelType("INVALID_TYPE")) {
        try await apiService.predictPrice(
        request: invalidRequest,
        authToken: authToken
        )
        }
    }
}


class EndToEndMockSecurityMiddleware: SecurityMiddlewareProtocol {
    func authenticate(request: APIRequest) async throws -> AuthResult {
    let authHeader = request.headers["Authorization"]
    if authHeader == "valid-token" || authHeader == "Bearer valid-token" {
    let user = AuthenticatedUser(
    userId: "user-1",
    username: "testuser",
    permissions: ["predict", "patterns"],
    roles: ["user"],
        tokenExpiry: Date().addingTimeInterval(3600)
    )
        return AuthResult(isAuthenticated: true, user: user, error: nil)
    } else {
        return AuthResult(isAuthenticated: false, user: nil, error: .invalidToken)
        }
    }

    func authorize(request: APIRequest, user: AuthenticatedUser) async throws -> Bool {
        return true
    }

    func validateRateLimit(request: APIRequest) async throws -> Bool {
        return true
    }

    func addSecurityHeaders(response: inout APIResponse) async throws {
        response.headers["X-Content-Type-Options"] = "nosniff"
    }

    func validateInput(request: APIRequest) async throws -> Bool {
        if request.path.contains("invalid") {
            return false
        }
        return true
    }
}
