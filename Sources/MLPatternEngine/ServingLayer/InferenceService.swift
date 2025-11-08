import Foundation
import Utils

public class InferenceService: InferenceServiceProtocol {
    private let predictionEngine: PredictionEngineProtocol
    private let cacheManager: CacheManagerProtocol
    private let circuitBreaker: CircuitBreakerProtocol
    private let logger: StructuredLogger

    public init(
        predictionEngine: PredictionEngineProtocol,
        cacheManager: CacheManagerProtocol,
        circuitBreaker: CircuitBreakerProtocol,
        logger: StructuredLogger
    ) {
        self.predictionEngine = predictionEngine
        self.cacheManager = cacheManager
        self.circuitBreaker = circuitBreaker
        self.logger = logger
    }

    public func predict(request: PredictionRequest) async throws -> PredictionResponse {
        let cacheKey = generateCacheKey(for: request)

        if let cachedResponse: PredictionResponse = try await cacheManager.get(key: cacheKey, type: PredictionResponse.self) {
            logger.debug(component: "InferenceService", event: "Cache hit for prediction request")
            return cachedResponse
        }

        let response = try await circuitBreaker.execute {
            try await predictionEngine.predictPrice(request: request)
        }

        let ttl = calculateTTL(for: request.timeHorizon)
        try await cacheManager.set(key: cacheKey, value: response, ttl: ttl)

        return response
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        var responses: [PredictionResponse] = []

        for request in requests {
            do {
                let response = try await predict(request: request)
                responses.append(response)
            } catch {
                logger.error(component: "InferenceService", event: "Failed to predict for \(request.symbol): \(error)")
            }
        }

        return responses
    }

    public func getServiceHealth() -> InferenceServiceHealth {
        let circuitBreakerState = circuitBreaker.getState()
        let isHealthy = circuitBreakerState != .open

        let cacheStats = cacheManager.getCacheStats()

        return InferenceServiceHealth(
            isHealthy: isHealthy,
            latency: 0.05, // Mock latency
            cacheHitRate: cacheStats.hitRate,
            activeModels: ["price_prediction", "volatility_prediction", "trend_classification"],
            lastUpdated: Date()
        )
    }

    public func warmupModels() async throws {
        logger.info(component: "InferenceService", event: "Warming up models")

        let warmupRequest = PredictionRequest(
            symbol: "BTC-USD",
            timeHorizon: 300, // 5 minutes
            features: [
                "price": 50000.0,
                "volatility": 0.02,
                "trend_strength": 0.1,
                "rsi": 50.0,
                "macd": 0.0
            ],
            modelType: .pricePrediction
        )

        _ = try await predict(request: warmupRequest)

        logger.info(component: "InferenceService", event: "Models warmed up successfully")
    }

    private func generateCacheKey(for request: PredictionRequest) -> String {
        let featuresHash = request.features.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")

        return "prediction:\(request.symbol):\(request.modelType.rawValue):\(request.timeHorizon):\(featuresHash.hashValue)"
    }

    private func calculateTTL(for timeHorizon: TimeInterval) -> TimeInterval {
        switch timeHorizon {
        case 0..<300: // Less than 5 minutes
            return 30 // 30 seconds
        case 300..<900: // 5-15 minutes
            return 120 // 2 minutes
        default: // 15+ minutes
            return 300 // 5 minutes
        }
    }
}

public class MockCacheManager: CacheManagerProtocol {
    private var cache: [String: (value: Data, expiry: Date)] = [:]
    private let logger: StructuredLogger
    private let cacheQueue = DispatchQueue(label: "MockCacheManager.queue", attributes: .concurrent)

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func get<T: Codable>(key: String, type: T.Type) async throws -> T? {
        return try cacheQueue.sync {
            guard let cached = cache[key],
                  cached.expiry > Date() else {
                return nil
            }

            do {
                return try JSONDecoder().decode(type, from: cached.value)
            } catch {
                logger.debug(component: "MockCacheManager", event: "Failed to decode cached value", data: [
                    "key": key,
                    "error": error.localizedDescription
                ])
                cache.removeValue(forKey: key)
                return nil
            }
        }
    }

    public func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let data = try encoder.encode(value)
            let expiry = Date().addingTimeInterval(ttl)

            cacheQueue.sync(flags: .barrier) {
                cache[key] = (data, expiry)
            }

            logger.debug(component: "MockCacheManager", event: "Cache value set", data: [
                "key": key,
                "size": String(data.count)
            ])
        } catch {
            logger.debug(component: "MockCacheManager", event: "Failed to cache value (non-fatal)", data: [
                "key": key,
                "error": error.localizedDescription
            ])
        }
    }

    public func invalidate(key: String) async throws {
        _ = cacheQueue.sync {
            cache.removeValue(forKey: key)
        }
    }

    public func invalidatePattern(pattern: String) async throws {
        let regex = try NSRegularExpression(pattern: pattern)

        let keysToRemove = cacheQueue.sync {
            cache.keys.filter { key in
                let range = NSRange(location: 0, length: key.utf16.count)
                return regex.firstMatch(in: key, options: [], range: range) != nil
            }
        }

        cacheQueue.sync {
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
    }

    public func getCacheStats() -> CacheStats {
        let now = Date()
        return cacheQueue.sync {
            _ = cache.values.filter { $0.expiry > now }
            let hitRate = 0.85
            let missRate = 1.0 - hitRate
            let totalKeys = cache.count
            let memoryUsage = Int64(cache.values.map { $0.value.count }.reduce(0, +))

            return CacheStats(
                hitRate: hitRate,
                missRate: missRate,
                totalKeys: totalKeys,
                memoryUsage: memoryUsage,
                lastUpdated: now
            )
        }
    }
}

public class CacheManagerFactory {
    public static func createCacheManager(type: CacheType, logger: StructuredLogger) -> CacheManagerProtocol {
        switch type {
        case .mock:
            return MockCacheManager(logger: logger)
        case .redis:
            let redisClient = RedisClient(
                host: "localhost",
                port: 6379,
                password: nil,
                database: 0,
                maxConnections: 10
            )
            return RedisCacheManager(redisClient: redisClient, logger: logger)
        }
    }
}

public enum CacheType: String, CaseIterable {
    case mock = "MOCK"
    case redis = "REDIS"
}

public class MockCircuitBreaker: CircuitBreakerProtocol {
    private var state: CircuitBreakerState = .closed
    private var failureCount = 0
    private let failureThreshold = 5
    private let recoveryTimeout: TimeInterval = 30.0
    private var lastFailureTime: Date?

    public init() {}

    public func execute<T>(_ operation: () async throws -> T) async throws -> T {
        if state == .open {
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) > recoveryTimeout {
                state = .halfOpen
            } else {
                throw CircuitBreakerError.circuitOpen
            }
        }

        do {
            let result = try await operation()

            if state == .halfOpen {
                state = .closed
                failureCount = 0
            }

            return result
        } catch {
            failureCount += 1
            lastFailureTime = Date()

            if failureCount >= failureThreshold {
                state = .open
            }

            throw error
        }
    }

    public func getState() -> CircuitBreakerState {
        return state
    }

    public func reset() async throws {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
    }
}

public enum CircuitBreakerError: Error {
    case circuitOpen
}
