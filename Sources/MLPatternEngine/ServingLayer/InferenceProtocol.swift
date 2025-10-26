import Foundation

public protocol InferenceServiceProtocol {
    func predict(request: PredictionRequest) async throws -> PredictionResponse
    func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse]
    func getServiceHealth() -> InferenceServiceHealth
    func warmupModels() async throws
}

public struct InferenceServiceHealth {
    public let isHealthy: Bool
    public let latency: TimeInterval
    public let cacheHitRate: Double
    public let activeModels: [String]
    public let lastUpdated: Date

    public init(isHealthy: Bool, latency: TimeInterval, cacheHitRate: Double, activeModels: [String], lastUpdated: Date) {
        self.isHealthy = isHealthy
        self.latency = latency
        self.cacheHitRate = cacheHitRate
        self.activeModels = activeModels
        self.lastUpdated = lastUpdated
    }
}

public protocol CacheManagerProtocol {
    func get<T: Codable>(key: String, type: T.Type) async throws -> T?
    func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async throws
    func invalidate(key: String) async throws
    func invalidatePattern(pattern: String) async throws
    func getCacheStats() -> CacheStats
}

public struct CacheStats {
    public let hitRate: Double
    public let missRate: Double
    public let totalKeys: Int
    public let memoryUsage: Int64
    public let lastUpdated: Date

    public init(hitRate: Double, missRate: Double, totalKeys: Int, memoryUsage: Int64, lastUpdated: Date) {
        self.hitRate = hitRate
        self.missRate = missRate
        self.totalKeys = totalKeys
        self.memoryUsage = memoryUsage
        self.lastUpdated = lastUpdated
    }
}

public protocol CircuitBreakerProtocol {
    func execute<T>(_ operation: () async throws -> T) async throws -> T
    func getState() -> CircuitBreakerState
    func reset() async throws
}

public enum CircuitBreakerState: String, CaseIterable {
    case closed = "CLOSED"
    case open = "OPEN"
    case halfOpen = "HALF_OPEN"
}
