import Foundation
import Utils

public protocol OperationalDashboardProtocol {
    func getSystemHealth() async throws -> SystemHealth
    func getPerformanceMetrics() async throws -> PerformanceMetrics
    func getModelMetrics() async throws -> ModelMetrics
    func getCacheMetrics() async throws -> CacheMetrics
    func getAlertStatus() async throws -> AlertStatus
    func getSystemInfo() async throws -> SystemInfo
}

public struct SystemHealth {
    public let overallStatus: HealthStatus
    public let services: [ServiceHealth]
    public let lastUpdated: Date
    public let uptime: TimeInterval
    public let version: String

    public init(overallStatus: HealthStatus, services: [ServiceHealth], lastUpdated: Date, uptime: TimeInterval, version: String) {
        self.overallStatus = overallStatus
        self.services = services
        self.lastUpdated = lastUpdated
        self.uptime = uptime
        self.version = version
    }
}

public enum HealthStatus: String, CaseIterable {
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case unhealthy = "UNHEALTHY"
    case unknown = "UNKNOWN"
}

public struct ServiceHealth {
    public let name: String
    public let status: HealthStatus
    public let latency: TimeInterval
    public let errorRate: Double
    public let lastCheck: Date
    public let details: [String: String]

    public init(name: String, status: HealthStatus, latency: TimeInterval, errorRate: Double, lastCheck: Date, details: [String: String]) {
        self.name = name
        self.status = status
        self.latency = latency
        self.errorRate = errorRate
        self.lastCheck = lastCheck
        self.details = details
    }
}

public struct PerformanceMetrics {
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let diskUsage: Double
    public let networkIn: Double
    public let networkOut: Double
    public let requestRate: Double
    public let responseTime: TimeInterval
    public let errorRate: Double
    public let timestamp: Date

    public init(cpuUsage: Double, memoryUsage: Double, diskUsage: Double, networkIn: Double, networkOut: Double, requestRate: Double, responseTime: TimeInterval, errorRate: Double, timestamp: Date) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.requestRate = requestRate
        self.responseTime = responseTime
        self.errorRate = errorRate
        self.timestamp = timestamp
    }
}

public struct ModelMetrics {
    public let totalModels: Int
    public let activeModels: Int
    public let modelPerformance: [ModelPerformance]
    public let averageAccuracy: Double
    public let totalPredictions: Int
    public let predictionsPerSecond: Double
    public let lastRetraining: Date?
    public let nextRetraining: Date?

    public init(totalModels: Int, activeModels: Int, modelPerformance: [ModelPerformance], averageAccuracy: Double, totalPredictions: Int, predictionsPerSecond: Double, lastRetraining: Date?, nextRetraining: Date?) {
        self.totalModels = totalModels
        self.activeModels = activeModels
        self.modelPerformance = modelPerformance
        self.averageAccuracy = averageAccuracy
        self.totalPredictions = totalPredictions
        self.predictionsPerSecond = predictionsPerSecond
        self.lastRetraining = lastRetraining
        self.nextRetraining = nextRetraining
    }
}

public struct ModelPerformance {
    public let modelId: String
    public let modelType: String
    public let accuracy: Double
    public let latency: TimeInterval
    public let predictionsCount: Int
    public let lastUsed: Date
    public let status: String

    public init(modelId: String, modelType: String, accuracy: Double, latency: TimeInterval, predictionsCount: Int, lastUsed: Date, status: String) {
        self.modelId = modelId
        self.modelType = modelType
        self.accuracy = accuracy
        self.latency = latency
        self.predictionsCount = predictionsCount
        self.lastUsed = lastUsed
        self.status = status
    }
}

public struct CacheMetrics {
    public let hitRate: Double
    public let missRate: Double
    public let totalKeys: Int
    public let memoryUsage: Int64
    public let evictions: Int
    public let connections: Int
    public let lastUpdated: Date

    public init(hitRate: Double, missRate: Double, totalKeys: Int, memoryUsage: Int64, evictions: Int, connections: Int, lastUpdated: Date) {
        self.hitRate = hitRate
        self.missRate = missRate
        self.totalKeys = totalKeys
        self.memoryUsage = memoryUsage
        self.evictions = evictions
        self.connections = connections
        self.lastUpdated = lastUpdated
    }
}

public struct AlertStatus {
    public let activeAlerts: [Alert]
    public let alertHistory: [Alert]
    public let alertRules: [AlertRule]
    public let lastUpdated: Date

    public init(activeAlerts: [Alert], alertHistory: [Alert], alertRules: [AlertRule], lastUpdated: Date) {
        self.activeAlerts = activeAlerts
        self.alertHistory = alertHistory
        self.alertRules = alertRules
        self.lastUpdated = lastUpdated
    }
}

public struct Alert {
    public let id: String
    public let severity: AlertSeverity
    public let title: String
    public let message: String
    public let source: String
    public let timestamp: Date
    public let acknowledged: Bool
    public let resolved: Bool

    public init(id: String, severity: AlertSeverity, title: String, message: String, source: String, timestamp: Date, acknowledged: Bool, resolved: Bool) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.source = source
        self.timestamp = timestamp
        self.acknowledged = acknowledged
        self.resolved = resolved
    }
}

public enum AlertSeverity: String, CaseIterable {
    case critical = "CRITICAL"
    case warning = "WARNING"
    case info = "INFO"
}

public struct AlertRule {
    public let id: String
    public let name: String
    public let condition: String
    public let severity: AlertSeverity
    public let enabled: Bool
    public let cooldown: TimeInterval

    public init(id: String, name: String, condition: String, severity: AlertSeverity, enabled: Bool, cooldown: TimeInterval) {
        self.id = id
        self.name = name
        self.condition = condition
        self.severity = severity
        self.enabled = enabled
        self.cooldown = cooldown
    }
}

public struct SystemInfo {
    public let uptime: TimeInterval
    public let memoryUsage: Int64
    public let memoryTotal: Int64
    public let cpuUsage: Double
    public let cpuCores: Int
    public let diskUsage: Int64
    public let diskTotal: Int64
    public let networkIn: Int64
    public let networkOut: Int64
    public let activeConnections: Int
    public let lastUpdated: Date

    public init(uptime: TimeInterval, memoryUsage: Int64, memoryTotal: Int64, cpuUsage: Double, cpuCores: Int, diskUsage: Int64, diskTotal: Int64, networkIn: Int64, networkOut: Int64, activeConnections: Int, lastUpdated: Date) {
        self.uptime = uptime
        self.memoryUsage = memoryUsage
        self.memoryTotal = memoryTotal
        self.cpuUsage = cpuUsage
        self.cpuCores = cpuCores
        self.diskUsage = diskUsage
        self.diskTotal = diskTotal
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.activeConnections = activeConnections
        self.lastUpdated = lastUpdated
    }
}

public class OperationalDashboard: OperationalDashboardProtocol {
    private let metricsCollector: MetricsCollector
    private let alertingSystem: AlertingSystem
    private let modelManager: ModelManagerProtocol
    private let cacheManager: CacheManagerProtocol
    private let logger: StructuredLogger
    private let startTime: Date

    public init(
        metricsCollector: MetricsCollector,
        alertingSystem: AlertingSystem,
        modelManager: ModelManagerProtocol,
        cacheManager: CacheManagerProtocol,
        logger: StructuredLogger
    ) {
        self.metricsCollector = metricsCollector
        self.alertingSystem = alertingSystem
        self.modelManager = modelManager
        self.cacheManager = cacheManager
        self.logger = logger
        self.startTime = Date()
    }

    public func getSystemHealth() async throws -> SystemHealth {
        let services = try await getServiceHealthStatuses()
        let overallStatus = determineOverallStatus(services: services)
        let uptime = Date().timeIntervalSince(startTime)

        return SystemHealth(
            overallStatus: overallStatus,
            services: services,
            lastUpdated: Date(),
            uptime: uptime,
            version: "1.0.0"
        )
    }

    public func getPerformanceMetrics() async throws -> PerformanceMetrics {
        _ = metricsCollector.getMetrics()
        _ = metricsCollector.getMetricsSummary()

        return PerformanceMetrics(
            cpuUsage: 0.3,
            memoryUsage: 0.4,
            diskUsage: 0.2,
            networkIn: 1000.0,
            networkOut: 500.0,
            requestRate: 150.0,
            responseTime: 0.05,
            errorRate: 0.01,
            timestamp: Date()
        )
    }

    public func getModelMetrics() async throws -> ModelMetrics {
        let models = modelManager.getAllModels()
        let activeModels = models.filter { $0.isActive }
        let modelPerformance = try await getModelPerformanceData(models: activeModels)
        let averageAccuracy = activeModels.map { $0.accuracy }.reduce(0, +) / Double(activeModels.count)

        let totalPredictions = 10000
        let predictionsPerSecond = 50.0

        return ModelMetrics(
            totalModels: models.count,
            activeModels: activeModels.count,
            modelPerformance: modelPerformance,
            averageAccuracy: averageAccuracy,
            totalPredictions: totalPredictions,
            predictionsPerSecond: predictionsPerSecond,
            lastRetraining: nil,
            nextRetraining: nil
        )
    }

    public func getCacheMetrics() async throws -> CacheMetrics {
        let cacheStats = cacheManager.getCacheStats()

        return CacheMetrics(
            hitRate: cacheStats.hitRate,
            missRate: cacheStats.missRate,
            totalKeys: cacheStats.totalKeys,
            memoryUsage: cacheStats.memoryUsage,
            evictions: 0,
            connections: 1,
            lastUpdated: cacheStats.lastUpdated
        )
    }

    public func getAlertStatus() async throws -> AlertStatus {
        let activeAlerts = alertingSystem.getActiveAlerts()
        let alertHistory = alertingSystem.getAlertHistory(limit: 100)
        let alertRules = alertingSystem.getAlertRules()

        return AlertStatus(
            activeAlerts: activeAlerts,
            alertHistory: alertHistory,
            alertRules: alertRules,
            lastUpdated: Date()
        )
    }

    public func getSystemInfo() async throws -> SystemInfo {
        let memoryInfo = getMemoryInfo()
        let cpuInfo = getCPUInfo()
        let diskInfo = getDiskInfo()
        let networkInfo = getNetworkInfo()

        return SystemInfo(
            uptime: getUptime(),
            memoryUsage: memoryInfo.used,
            memoryTotal: memoryInfo.total,
            cpuUsage: cpuInfo.usage,
            cpuCores: cpuInfo.cores,
            diskUsage: diskInfo.used,
            diskTotal: diskInfo.total,
            networkIn: networkInfo.inbound,
            networkOut: networkInfo.outbound,
            activeConnections: try await getActiveConnections(),
            lastUpdated: Date()
        )
    }


    // MARK: - Private Helper Methods

    private func getMemoryInfo() -> (used: Int64, total: Int64) {
        let totalMemory = Int64(8 * 1024 * 1024 * 1024) // 8GB mock
        let usedMemory = Int64.random(in: 2_000_000_000...6_000_000_000) // 2-6GB
        return (used: usedMemory, total: totalMemory)
    }

    private func getCPUInfo() -> (usage: Double, cores: Int) {
        let usage = Double.random(in: 10...80)
        let cores = 8
        return (usage: usage, cores: cores)
    }

    private func getDiskInfo() -> (used: Int64, total: Int64) {
        let totalDisk = Int64(500 * 1024 * 1024 * 1024) // 500GB
        let usedDisk = Int64.random(in: 100_000_000_000...400_000_000_000) // 100-400GB
        return (used: usedDisk, total: totalDisk)
    }

    private func getNetworkInfo() -> (inbound: Int64, outbound: Int64) {
        let inbound = Int64.random(in: 1_000_000...100_000_000) // 1-100MB
        let outbound = Int64.random(in: 1_000_000...50_000_000) // 1-50MB
        return (inbound: inbound, outbound: outbound)
    }

    private func getUptime() -> TimeInterval {
        return Date().timeIntervalSince(Date().addingTimeInterval(-86400 * 7)) // 7 days mock
    }

    private func getActiveConnections() async throws -> Int {
        return Int.random(in: 10...100)
    }

    private func calculateErrorRate(metrics: [String: MetricValue]) -> Double {
        let totalRequests = metrics["api_requests_total"]?.sum ?? 0
        let errorRequests = metrics["api_errors_total"]?.sum ?? 0

        guard totalRequests > 0 else { return 0.0 }
        return errorRequests / totalRequests
    }

    private func calculateAvailability(metrics: [String: MetricValue]) -> Double {
        let uptime = getUptime()
        let downtime = metrics["system_downtime"]?.sum ?? 0

        guard uptime > 0 else { return 0.0 }
        return max(0.0, (uptime - downtime) / uptime)
    }

    private func getMemoryUsage() -> Double {
        let info = getMemoryInfo()
        return Double(info.used) / Double(info.total)
    }

    private func getCPUUsage() -> Double {
        return getCPUInfo().usage
    }

    private func getActiveModelCount() async throws -> Int {
        let models = modelManager.getAllModels()
        return models.filter { $0.isActive }.count
    }

    private func getLastRetrainingTime() async throws -> Date? {
        // Mock implementation - would query retraining pipeline
        return Date().addingTimeInterval(-3600) // 1 hour ago
    }

    private func getNextRetrainingTime() async throws -> Date? {
        // Mock implementation - would query retraining pipeline
        return Date().addingTimeInterval(3600) // 1 hour from now
    }

    private func getCacheEvictions() async throws -> Int {
        return Int.random(in: 0...1000)
    }

    private func getCacheConnections() async throws -> Int {
        return Int.random(in: 1...10)
    }

    private func getServiceHealthStatuses() async throws -> [ServiceHealth] {
        var services: [ServiceHealth] = []

        // ML Engine Health
        let mlEngineHealth = try await checkMLEngineHealth()
        services.append(mlEngineHealth)

        // Cache Health
        let cacheHealth = try await checkCacheHealth()
        services.append(cacheHealth)

        // Database Health
        let databaseHealth = try await checkDatabaseHealth()
        services.append(databaseHealth)

        // API Health
        let apiHealth = try await checkAPIHealth()
        services.append(apiHealth)

        return services
    }

    private func checkMLEngineHealth() async throws -> ServiceHealth {
        let startTime = Date()

        do {
            // Simulate health check
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            let latency = Date().timeIntervalSince(startTime)

            return ServiceHealth(
                name: "ML Engine",
                status: .healthy,
                latency: latency,
                errorRate: 0.01,
                lastCheck: Date(),
                details: [
                    "models_loaded": "3",
                    "memory_usage": "256MB"
                ]
            )
        } catch {
            return ServiceHealth(
                name: "ML Engine",
                status: .unhealthy,
                latency: Date().timeIntervalSince(startTime),
                errorRate: 1.0,
                lastCheck: Date(),
                details: ["error": error.localizedDescription]
            )
        }
    }

    private func checkCacheHealth() async throws -> ServiceHealth {
        let startTime = Date()

        let stats = cacheManager.getCacheStats()
        let latency = Date().timeIntervalSince(startTime)

        let status: HealthStatus = stats.hitRate > 0.8 ? .healthy : .degraded

        return ServiceHealth(
            name: "Cache",
            status: status,
            latency: latency,
            errorRate: 0.0,
            lastCheck: Date(),
            details: [
                "hit_rate": String(stats.hitRate),
                "total_keys": String(stats.totalKeys)
            ]
        )
    }

    private func checkDatabaseHealth() async throws -> ServiceHealth {
        let startTime = Date()

        do {
            // Simulate database health check
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            let latency = Date().timeIntervalSince(startTime)

            return ServiceHealth(
                name: "Database",
                status: .healthy,
                latency: latency,
                errorRate: 0.0,
                lastCheck: Date(),
                details: [
                    "connections": "5",
                    "size": "1.2GB"
                ]
            )
        } catch {
            return ServiceHealth(
                name: "Database",
                status: .unhealthy,
                latency: Date().timeIntervalSince(startTime),
                errorRate: 1.0,
                lastCheck: Date(),
                details: ["error": error.localizedDescription]
            )
        }
    }

    private func checkAPIHealth() async throws -> ServiceHealth {
        let startTime = Date()

        do {
            // Simulate API health check
            try await Task.sleep(nanoseconds: 2_000_000) // 2ms
            let latency = Date().timeIntervalSince(startTime)

            return ServiceHealth(
                name: "API",
                status: .healthy,
                latency: latency,
                errorRate: 0.02,
                lastCheck: Date(),
                details: [
                    "requests_per_second": "150",
                    "active_connections": "25"
                ]
            )
        } catch {
            return ServiceHealth(
                name: "API",
                status: .unhealthy,
                latency: Date().timeIntervalSince(startTime),
                errorRate: 1.0,
                lastCheck: Date(),
                details: ["error": error.localizedDescription]
            )
        }
    }

    private func determineOverallStatus(services: [ServiceHealth]) -> HealthStatus {
        let unhealthyCount = services.filter { $0.status == .unhealthy }.count
        let degradedCount = services.filter { $0.status == .degraded }.count

        if unhealthyCount > 0 {
            return .unhealthy
        } else if degradedCount > 0 {
            return .degraded
        } else {
            return .healthy
        }
    }

    private func getModelPerformanceData(models: [ModelInfo]) async throws -> [ModelPerformance] {
        return models.map { model in
            ModelPerformance(
                modelId: model.modelId,
                modelType: model.modelType.rawValue,
                accuracy: model.accuracy,
                latency: 50.0, // Mock latency
                predictionsCount: Int.random(in: 1000...10000),
                lastUsed: Date().addingTimeInterval(-Double.random(in: 0...3600)),
                status: model.isActive ? "active" : "inactive"
            )
        }
    }
}
