import Foundation
import Utils

public protocol OperationalDashboardProtocol {
    func getSystemHealth() async throws -> [ServiceHealth]
    func getAlerts() async throws -> [Alert]
    func getMetrics() async throws -> [String: Double]
}

public struct ServiceHealth: Codable {
    public let serviceName: String
    public let status: String
    public let lastCheck: Date
    public let responseTime: Double
    public let errorRate: Double

    public init(serviceName: String, status: String, lastCheck: Date, responseTime: Double, errorRate: Double) {
        self.serviceName = serviceName
        self.status = status
        self.lastCheck = lastCheck
        self.responseTime = responseTime
        self.errorRate = errorRate
    }
}

public struct Alert: Codable {
    public let id: UUID
    public let title: String
    public let message: String
    public let severity: AlertSeverity
    public let timestamp: Date
    public let service: String

    public init(id: UUID = UUID(), title: String, message: String, severity: AlertSeverity, timestamp: Date, service: String) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.timestamp = timestamp
        self.service = service
    }
}

public enum AlertSeverity: String, CaseIterable, Codable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

public struct AlertSummary: Codable {
    public let severity: AlertSeverity
    public let count: Int
    public let latestTitle: String?

    public init(severity: AlertSeverity, count: Int, latestTitle: String?) {
        self.severity = severity
        self.count = count
        self.latestTitle = latestTitle
    }
}

public protocol HealthCheckEndpointsProtocol {
    func getHealthCheck() async throws -> HealthCheckResponse
    func getReadinessCheck() async throws -> ReadinessCheckResponse
    func getLivenessCheck() async throws -> LivenessCheckResponse
    func getDetailedHealthCheck() async throws -> DetailedHealthCheckResponse
}

public struct HealthCheckResponse {
    public let status: String
    public let timestamp: Date
    public let version: String
    public let uptime: TimeInterval

    public init(status: String, timestamp: Date, version: String, uptime: TimeInterval) {
        self.status = status
        self.timestamp = timestamp
        self.version = version
        self.uptime = uptime
    }
}

public struct ReadinessCheckResponse {
    public let ready: Bool
    public let checks: [DependencyCheck]
    public let timestamp: Date

    public init(ready: Bool, checks: [DependencyCheck], timestamp: Date) {
        self.ready = ready
        self.checks = checks
        self.timestamp = timestamp
    }
}

public struct LivenessCheckResponse {
    public let alive: Bool
    public let timestamp: Date
    public let uptime: TimeInterval

    public init(alive: Bool, timestamp: Date, uptime: TimeInterval) {
        self.alive = alive
        self.timestamp = timestamp
        self.uptime = uptime
    }
}

public struct DetailedHealthCheckResponse {
    public let overallStatus: String
    public let services: [ServiceStatus]
    public let metrics: SystemMetrics
    public let alerts: [AlertSummary]
    public let timestamp: Date

    public init(overallStatus: String, services: [ServiceStatus], metrics: SystemMetrics, alerts: [AlertSummary], timestamp: Date) {
        self.overallStatus = overallStatus
        self.services = services
        self.metrics = metrics
        self.alerts = alerts
        self.timestamp = timestamp
    }
}

public struct DependencyCheck {
    public let name: String
    public let status: String
    public let latency: TimeInterval
    public let error: String?
    public let lastCheck: Date

    public init(name: String, status: String, latency: TimeInterval, error: String?, lastCheck: Date) {
        self.name = name
        self.status = status
        self.latency = latency
        self.error = error
        self.lastCheck = lastCheck
    }
}

public struct ServiceStatus {
    public let name: String
    public let status: String
    public let health: Double
    public let latency: TimeInterval
    public let lastCheck: Date
    public let details: [String: String]

    public init(name: String, status: String, health: Double, latency: TimeInterval, lastCheck: Date, details: [String: String]) {
        self.name = name
        self.status = status
        self.health = health
        self.latency = latency
        self.lastCheck = lastCheck
        self.details = details
    }
}

public struct SystemMetrics {
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let diskUsage: Double
    public let networkIn: Double
    public let networkOut: Double
    public let requestRate: Double
    public let responseTime: TimeInterval
    public let errorRate: Double

    public init(cpuUsage: Double, memoryUsage: Double, diskUsage: Double, networkIn: Double, networkOut: Double, requestRate: Double, responseTime: TimeInterval, errorRate: Double) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.requestRate = requestRate
        self.responseTime = responseTime
        self.errorRate = errorRate
    }
}


public class HealthCheckEndpoints: HealthCheckEndpointsProtocol {
    private let operationalDashboard: OperationalDashboardProtocol
    private let logger: StructuredLogger
    private let startTime: Date

    public init(operationalDashboard: OperationalDashboardProtocol, logger: StructuredLogger) {
        self.operationalDashboard = operationalDashboard
        self.logger = logger
        self.startTime = Date()
    }

    public func getHealthCheck() async throws -> HealthCheckResponse {
        let systemHealth = try await operationalDashboard.getSystemHealth()
        let status = "healthy" // Default status since we don't have overallStatus

        logger.debug(component: "HealthCheckEndpoints", event: "Health check requested", data: [
            "status": status,
            "services_count": String(systemHealth.count)
        ])

        return HealthCheckResponse(
            status: status,
            timestamp: Date(),
            version: "1.0.0", // Default version
            uptime: 0 // Default uptime
        )
    }

    public func getReadinessCheck() async throws -> ReadinessCheckResponse {
        let checks = try await performReadinessChecks()
        let ready = checks.allSatisfy { $0.status == "healthy" }

        logger.debug(component: "HealthCheckEndpoints", event: "Readiness check requested", data: [
            "ready": String(ready),
            "checks": String(checks.count)
        ])

        return ReadinessCheckResponse(
            ready: ready,
            checks: checks,
            timestamp: Date()
        )
    }

    public func getLivenessCheck() async throws -> LivenessCheckResponse {
        let uptime = Date().timeIntervalSince(startTime)
        let alive = uptime > 0 // Simple liveness check

        logger.debug(component: "HealthCheckEndpoints", event: "Liveness check requested", data: [
            "alive": String(alive),
            "uptime": String(uptime)
        ])

        return LivenessCheckResponse(
            alive: alive,
            timestamp: Date(),
            uptime: uptime
        )
    }

    public func getDetailedHealthCheck() async throws -> DetailedHealthCheckResponse {
        let systemHealth = try await operationalDashboard.getSystemHealth()
        let performanceMetrics = try await operationalDashboard.getMetrics()
        let alerts = try await operationalDashboard.getAlerts()

        let services = systemHealth.map { service in
            ServiceStatus(
                name: service.serviceName,
                status: service.status.lowercased(),
                health: calculateHealthScore(service: service),
                latency: service.responseTime,
                lastCheck: service.lastCheck,
                details: ["status": service.status]
            )
        }

        let metrics = SystemMetrics(
            cpuUsage: performanceMetrics["cpu_usage"] ?? 0.0,
            memoryUsage: performanceMetrics["memory_usage"] ?? 0.0,
            diskUsage: performanceMetrics["disk_usage"] ?? 0.0,
            networkIn: performanceMetrics["network_in"] ?? 0.0,
            networkOut: performanceMetrics["network_out"] ?? 0.0,
            requestRate: performanceMetrics["request_rate"] ?? 0.0,
            responseTime: performanceMetrics["response_time"] ?? 0.0,
            errorRate: performanceMetrics["error_rate"] ?? 0.0
        )

        let alertSummaries = groupAlertsBySeverity(alerts)

        logger.debug(component: "HealthCheckEndpoints", event: "Detailed health check requested", data: [
            "overallStatus": "healthy",
            "servicesCount": String(services.count),
            "alertsCount": String(alerts.count)
        ])

        return DetailedHealthCheckResponse(
            overallStatus: "healthy",
            services: services,
            metrics: metrics,
            alerts: alertSummaries,
            timestamp: Date()
        )
    }

    private func performReadinessChecks() async throws -> [DependencyCheck] {
        var checks: [DependencyCheck] = []

        // Check ML Engine
        let mlEngineCheck = try await checkMLEngineReadiness()
        checks.append(mlEngineCheck)

        // Check Cache
        let cacheCheck = try await checkCacheReadiness()
        checks.append(cacheCheck)

        // Check Database
        let databaseCheck = try await checkDatabaseReadiness()
        checks.append(databaseCheck)

        // Check External APIs
        let apiCheck = try await checkExternalAPIReadiness()
        checks.append(apiCheck)

        return checks
    }

    private func checkMLEngineReadiness() async throws -> DependencyCheck {
        let startTime = Date()

        do {
            // Simulate ML engine readiness check
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            let latency = Date().timeIntervalSince(startTime)

            return DependencyCheck(
                name: "ML Engine",
                status: "healthy",
                latency: latency,
                error: nil,
                lastCheck: Date()
            )
        } catch {
            return DependencyCheck(
                name: "ML Engine",
                status: "unhealthy",
                latency: Date().timeIntervalSince(startTime),
                error: error.localizedDescription,
                lastCheck: Date()
            )
        }
    }

    private func checkCacheReadiness() async throws -> DependencyCheck {
        let startTime = Date()

        do {
            // Simulate cache readiness check
            try await Task.sleep(nanoseconds: 2_000_000) // 2ms
            let latency = Date().timeIntervalSince(startTime)

            return DependencyCheck(
                name: "Cache",
                status: "healthy",
                latency: latency,
                error: nil,
                lastCheck: Date()
            )
        } catch {
            return DependencyCheck(
                name: "Cache",
                status: "unhealthy",
                latency: Date().timeIntervalSince(startTime),
                error: error.localizedDescription,
                lastCheck: Date()
            )
        }
    }

    private func checkDatabaseReadiness() async throws -> DependencyCheck {
        let startTime = Date()

        do {
            // Simulate database readiness check
            try await Task.sleep(nanoseconds: 3_000_000) // 3ms
            let latency = Date().timeIntervalSince(startTime)

            return DependencyCheck(
                name: "Database",
                status: "healthy",
                latency: latency,
                error: nil,
                lastCheck: Date()
            )
        } catch {
            return DependencyCheck(
                name: "Database",
                status: "unhealthy",
                latency: Date().timeIntervalSince(startTime),
                error: error.localizedDescription,
                lastCheck: Date()
            )
        }
    }

    private func checkExternalAPIReadiness() async throws -> DependencyCheck {
        let startTime = Date()

        do {
            // Simulate external API readiness check
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            let latency = Date().timeIntervalSince(startTime)

            return DependencyCheck(
                name: "External APIs",
                status: "healthy",
                latency: latency,
                error: nil,
                lastCheck: Date()
            )
        } catch {
            return DependencyCheck(
                name: "External APIs",
                status: "unhealthy",
                latency: Date().timeIntervalSince(startTime),
                error: error.localizedDescription,
                lastCheck: Date()
            )
        }
    }

    private func calculateHealthScore(service: ServiceHealth) -> Double {
        var score = 1.0

        // Reduce score based on error rate
        score -= service.errorRate

        // Reduce score based on latency (if > 100ms)
        if service.responseTime > 0.1 {
            score -= min(0.5, (service.responseTime - 0.1) * 2)
        }

        return max(0.0, min(1.0, score))
    }

    private func groupAlertsBySeverity(_ alerts: [Alert]) -> [AlertSummary] {
        let grouped = Dictionary(grouping: alerts) { $0.severity }

        return AlertSeverity.allCases.map { severity in
            let alertsForSeverity = grouped[severity] ?? []
            let latest = alertsForSeverity.max(by: { $0.timestamp < $1.timestamp })?.title

            return AlertSummary(
                severity: severity,
                count: alertsForSeverity.count,
                latestTitle: latest
            )
        }
    }
}
