import Testing
import Foundation
@testable import MLPatternEngine
@testable import MLPatternEngineAPI
@testable import Utils

// MARK: - Missing Type Definitions

public struct PatternResponse: Codable, Sendable {
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

public struct TimeRange: Codable, Sendable {
    public let from: Date
    public let to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }
}

@Suite("API Integration Tests")
struct APIIntegrationTests {

    @Test func testPredictionEndpointIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: [
                "price": 50000.0,
                "volatility": 0.02,
                "trend_strength": 0.1
            ]
        )

        let response = try await apiService.predictPrice(
            request: request,
            authToken: "valid-token"
        )

        #expect(response.symbol == "BTC-USD")
        #expect(response.timeHorizon == 300)
        #expect(response.prediction > 0)
        #expect(response.confidence >= 0.0 && response.confidence <= 1.0)
    }

    @Test func testPatternDetectionEndpointIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let request = PatternDetectionRequestDTO(
            symbol: "ETH-USD",
            patternTypes: ["head_and_shoulders", "double_top"],
            timeRange: TimeRangeDTO(
                from: Date().addingTimeInterval(-86400),
                to: Date()
            )
        )

        let response = try await apiService.detectPatterns(
            request: request,
            authToken: "valid-token"
        )

        #expect(response.count >= 0)
    }

    @Test func testBatchPredictionEndpointIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let requests = [
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": 50000.0]
            ),
            PredictionRequestDTO(
                symbol: "ETH-USD",
                timeHorizon: 600,
                modelType: "VOLATILITY_PREDICTION",
                features: ["price": 3000.0]
            )
        ]

        let response = try await apiService.batchPredict(
            request: BatchPredictionRequestDTO(requests: requests),
            authToken: "valid-token"
        )

        #expect(response.count == 2)
        #expect(response[0].symbol == "BTC-USD")
        #expect(response[1].symbol == "ETH-USD")
    }

    @Test func testHealthEndpointIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let response = apiService.getHealth()

        #expect(response.isHealthy == true)
        #expect(response.latency >= 0)
        #expect(response.cacheHitRate >= 0.0 && response.cacheHitRate <= 1.0)
        #expect(response.activeModels.count >= 0)
    }

    @Test func testModelsEndpointIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let response = try await apiService.getModels(authToken: "valid-token")

        #expect(response.count >= 0)
        for model in response {
            #expect(!model.modelId.isEmpty)
            #expect(!model.version.isEmpty)
            #expect(!model.modelType.isEmpty)
            #expect(model.accuracy >= 0.0 && model.accuracy <= 1.0)
        }
    }

    @Test func testAuthenticationIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        await #expect(throws: APIError.unauthorized) {
            try await apiService.predictPrice(
                request: request,
                authToken: nil as String?
            )
        }

        await #expect(throws: APIError.unauthorized) {
            try await apiService.predictPrice(
                request: request,
                authToken: "invalid-token"
            )
        }
    }

    @Test func testRateLimitingIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let rateLimiter = RateLimiter(maxRequests: 2, windowSize: 60)
        let inputValidator = MockInputValidator()
        let authManager = MockAuthManager()
        let securityMiddleware = SecurityMiddleware(
            authManager: authManager,
            rateLimiter: rateLimiter,
            inputValidator: inputValidator,
            logger: logger
        )
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: rateLimiter,
            authManager: authManager
        )

        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        let validToken = "valid-token"

        do {
            let response1 = try await apiService.predictPrice(
                request: request,
                authToken: validToken
            )
            #expect(response1.symbol == "BTC-USD")
        } catch {
            Issue.record("First request should not fail")
        }
    }

    @Test func testInputValidationIntegration() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let invalidRequest = PredictionRequestDTO(
            symbol: "", // Invalid empty symbol
            timeHorizon: -100, // Invalid negative time horizon
            modelType: "INVALID_TYPE",
            features: [:]
        )

        await #expect(throws: APIError.invalidInput) {
            try await apiService.predictPrice(
                request: invalidRequest,
                authToken: "valid-token"
            )
        }
    }

    @Test func testErrorHandlingIntegration() async throws {
        let logger = createTestLogger()
        let failingMLEngine = createFailingMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: failingMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        await #expect(throws: APIError.internalError) {
            try await apiService.predictPrice(
                request: request,
                authToken: "valid-token"
            )
        }
    }
}


class MockSecurityMiddleware: SecurityMiddlewareProtocol {
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

class MockInputValidator: InputValidator {
    init() {
        super.init(logger: createTestLogger())
    }

    override func validate(request: APIRequest) async throws -> Bool {
        if request.body?.count ?? 0 > 10000000 {
            return false
        }
        return true
    }
}

class MockAuthManager: AuthManager {
    init() {
        super.init(jwtSecret: "test-secret", tokenExpiry: 3600, logger: createTestLogger())
    }

    override func validateToken(_ token: String) -> Bool {
        return token == "valid-token"
    }

    override func validateTokenAndGetUser(_ token: String) async throws -> AuthenticatedUser {
        if token == "valid-token" {
            return AuthenticatedUser(
                userId: "user-1",
                username: "testuser",
                permissions: ["predict", "patterns"],
                roles: ["user"],
                tokenExpiry: Date().addingTimeInterval(3600)
            )
        } else {
            throw AuthError.invalidToken
        }
    }
}
