import Foundation
import Utils

public class RedisCacheManager: CacheManagerProtocol {
    private let redisClient: RedisClient
    private let logger: StructuredLogger
    private let connectionPool: RedisConnectionPool
    private var stats = RedisCacheStats()

    public init(redisClient: RedisClient, logger: StructuredLogger) {
        self.redisClient = redisClient
        self.logger = logger
        self.connectionPool = RedisConnectionPool(redisClient: redisClient)
    }

    public func get<T: Codable>(key: String, type: T.Type) async throws -> T? {
        let startTime = Date()

        do {
            let connection = try await connectionPool.getConnection()
            defer { connectionPool.returnConnection(connection) }

            let data = try await connection.get(key: key)

            if let data = data {
                let value = try JSONDecoder().decode(type, from: data)
                stats.recordHit()

                logger.debug(component: "RedisCacheManager", event: "Cache hit", data: [
                    "key": key,
                    "latency": String(Date().timeIntervalSince(startTime) * 1000)
                ])

                return value
            } else {
                stats.recordMiss()

                logger.debug(component: "RedisCacheManager", event: "Cache miss", data: [
                    "key": key,
                    "latency": String(Date().timeIntervalSince(startTime) * 1000)
                ])

                return nil
            }
        } catch {
            stats.recordError()
            logger.error(component: "RedisCacheManager", event: "Failed to get from cache", data: [
                "key": key,
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    public func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async throws {
        let startTime = Date()

        do {
            let connection = try await connectionPool.getConnection()
            defer { connectionPool.returnConnection(connection) }

            let data = try JSONEncoder().encode(value)
            try await connection.set(key: key, value: data, ttl: Int(ttl))

            stats.recordSet()

            logger.debug(component: "RedisCacheManager", event: "Value cached", data: [
                "key": key,
                "ttl": String(ttl),
                "size": String(data.count),
                "latency": String(Date().timeIntervalSince(startTime) * 1000)
            ])
        } catch {
            stats.recordError()
            logger.error(component: "RedisCacheManager", event: "Failed to set cache", data: [
                "key": key,
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    public func invalidate(key: String) async throws {
        do {
            let connection = try await connectionPool.getConnection()
            defer { connectionPool.returnConnection(connection) }

            try await connection.del(key: key)

            logger.debug(component: "RedisCacheManager", event: "Key invalidated", data: [
                "key": key
            ])
        } catch {
            logger.error(component: "RedisCacheManager", event: "Failed to invalidate key", data: [
                "key": key,
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    public func invalidatePattern(pattern: String) async throws {
        do {
            let connection = try await connectionPool.getConnection()
            defer { connectionPool.returnConnection(connection) }

            let keys = try await connection.keys(pattern: pattern)

            if !keys.isEmpty {
                try await connection.del(keys: keys)
            }

            logger.debug(component: "RedisCacheManager", event: "Pattern invalidated", data: [
                "pattern": pattern,
                "keysDeleted": String(keys.count)
            ])
        } catch {
            logger.error(component: "RedisCacheManager", event: "Failed to invalidate pattern", data: [
                "pattern": pattern,
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    public func getCacheStats() -> CacheStats {
        return stats.getCurrentStats()
    }
}

public class RedisClient {
    private let host: String
    private let port: Int
    private let password: String?
    private let database: Int
    private let maxConnections: Int

    public init(host: String, port: Int, password: String? = nil, database: Int = 0, maxConnections: Int = 10) {
        self.host = host
        self.port = port
        self.password = password
        self.database = database
        self.maxConnections = maxConnections
    }

    public func createConnection() async throws -> RedisConnection {
        return RedisConnection(
            host: host,
            port: port,
            password: password,
            database: database
        )
    }
}

public class RedisConnection {
    private let host: String
    private let port: Int
    private let password: String?
    private let database: Int
    private var isConnected = false

    public init(host: String, port: Int, password: String?, database: Int) {
        self.host = host
        self.port = port
        self.password = password
        self.database = database
    }

    public func connect() async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // Simulate connection time
        isConnected = true
    }

    public func disconnect() async throws {
        isConnected = false
    }

    public func get(key: String) async throws -> Data? {
        guard isConnected else {
            throw RedisError.notConnected
        }

        try await Task.sleep(nanoseconds: 1_000_000) // Simulate network latency

        return Data() // Mock implementation
    }

    public func set(key: String, value: Data, ttl: Int) async throws {
        guard isConnected else {
            throw RedisError.notConnected
        }

        try await Task.sleep(nanoseconds: 1_000_000) // Simulate network latency
    }

    public func del(key: String) async throws {
        guard isConnected else {
            throw RedisError.notConnected
        }

        try await Task.sleep(nanoseconds: 500_000) // Simulate network latency
    }

    public func del(keys: [String]) async throws {
        guard isConnected else {
            throw RedisError.notConnected
        }

        try await Task.sleep(nanoseconds: UInt64(keys.count * 500_000)) // Simulate network latency
    }

    public func keys(pattern: String) async throws -> [String] {
        guard isConnected else {
            throw RedisError.notConnected
        }

        try await Task.sleep(nanoseconds: 2_000_000) // Simulate network latency

        return [] // Mock implementation
    }
}

public final class RedisConnectionPool: @unchecked Sendable {
    private let redisClient: RedisClient
    private var availableConnections: [RedisConnection] = []
    private var allConnections: [RedisConnection] = []
    private let maxConnections: Int
    private let semaphore: DispatchSemaphore

    public init(redisClient: RedisClient, maxConnections: Int = 10) {
        self.redisClient = redisClient
        self.maxConnections = maxConnections
        self.semaphore = DispatchSemaphore(value: maxConnections)
    }

    public func getConnection() async throws -> RedisConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()

                if let connection = self.availableConnections.popLast() {
                    continuation.resume(returning: connection)
                } else if self.allConnections.count < self.maxConnections {
                    Task { [weak self] in
                        guard let self = self else { return }
                        do {
                            let connection = try await self.redisClient.createConnection()
                            try await connection.connect()
                            self.allConnections.append(connection)
                            continuation.resume(returning: connection)
                        } catch {
                            self.semaphore.signal()
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    let connection = self.allConnections.randomElement()!
                    continuation.resume(returning: connection)
                }
            }
        }
    }

    public func returnConnection(_ connection: RedisConnection) {
        availableConnections.append(connection)
        semaphore.signal()
    }

    public func closeAllConnections() async throws {
        for connection in allConnections {
            try await connection.disconnect()
        }
        allConnections.removeAll()
        availableConnections.removeAll()
    }
}

public enum RedisError: Error {
    case notConnected
    case connectionFailed
    case operationFailed
    case invalidKey
    case serializationFailed
}

public class RedisCacheStats {
    private var hits: Int = 0
    private var misses: Int = 0
    private var sets: Int = 0
    private var errors: Int = 0
    private let lock = NSLock()

    public func recordHit() {
        lock.lock()
        defer { lock.unlock() }
        hits += 1
    }

    public func recordMiss() {
        lock.lock()
        defer { lock.unlock() }
        misses += 1
    }

    public func recordSet() {
        lock.lock()
        defer { lock.unlock() }
        sets += 1
    }

    public func recordError() {
        lock.lock()
        defer { lock.unlock() }
        errors += 1
    }

    public func getCurrentStats() -> CacheStats {
        lock.lock()
        defer { lock.unlock() }

        let total = hits + misses
        let hitRate = total > 0 ? Double(hits) / Double(total) : 0.0
        let missRate = 1.0 - hitRate

        return CacheStats(
            hitRate: hitRate,
            missRate: missRate,
            totalKeys: 0, // Would need to query Redis for this
            memoryUsage: 0, // Would need to query Redis for this
            lastUpdated: Date()
        )
    }
}
