import Foundation

public struct TigerBeetleSLO: Sendable {
    public let p95LatencyMs: Double
    public let errorRatePercent: Double
    public let maxBacklog: Int
    public let maxDrift: Double
    public let maxDriftUSD: Double

    public static let production = TigerBeetleSLO(
        p95LatencyMs: 10.0,
        errorRatePercent: 0.5,
        maxBacklog: 1000,
        maxDrift: 1e-8,
        maxDriftUSD: 0.01
    )

    public init(
        p95LatencyMs: Double,
        errorRatePercent: Double,
        maxBacklog: Int,
        maxDrift: Double,
        maxDriftUSD: Double
    ) {
        self.p95LatencyMs = p95LatencyMs
        self.errorRatePercent = errorRatePercent
        self.maxBacklog = maxBacklog
        self.maxDrift = maxDrift
        self.maxDriftUSD = maxDriftUSD
    }
}

public struct AlertThresholds {
    public init() {}
    public let p99LatencyWarnMs: Double = 100.0
    public let p99LatencyWarnDurationMinutes: Int = 5
    public let errorRateTripPercent: Double = 1.0
    public let errorRateTripDurationMinutes: Int = 1
    public let driftPageUnits: Double = 1e-8
    public let driftPageUSD: Double = 0.01
}

public actor SLOMonitor {
    private let slo: TigerBeetleSLO
    private let thresholds: AlertThresholds
    private var p99LatencyHistory: [Date: TimeInterval] = [:]
    private var errorRateHistory: [Date: Double] = [:]

    public init(slo: TigerBeetleSLO = .production, thresholds: AlertThresholds = AlertThresholds()) {
        self.slo = slo
        self.thresholds = thresholds
    }

    public func recordP99Latency(_ latency: TimeInterval) {
        p99LatencyHistory[Date()] = latency
        cleanupOldHistory()
    }

    public func recordErrorRate(_ rate: Double) {
        errorRateHistory[Date()] = rate
        cleanupOldHistory()
    }

    public func checkSLOs(
        p95Latency: TimeInterval,
        errorRate: Double,
        backlog: Int,
        drift: Double,
        driftUSD: Double
    ) -> [SLOViolation] {
        var violations: [SLOViolation] = []

        if p95Latency * 1000 > slo.p95LatencyMs {
            violations.append(.latency(p95Latency * 1000, slo.p95LatencyMs))
        }

        if errorRate * 100 > slo.errorRatePercent {
            violations.append(.errorRate(errorRate * 100, slo.errorRatePercent))
        }

        if backlog > slo.maxBacklog {
            violations.append(.backlog(backlog, slo.maxBacklog))
        }

        if drift > slo.maxDrift || driftUSD > slo.maxDriftUSD {
            violations.append(.drift(drift, driftUSD, slo.maxDrift, slo.maxDriftUSD))
        }

        return violations
    }

    public func checkAlertConditions() -> [Alert] {
        var alerts: [Alert] = []

        let recentP99 = p99LatencyHistory.filter {
            Date().timeIntervalSince($0.key) <= Double(thresholds.p99LatencyWarnDurationMinutes * 60)
        }

        if recentP99.values.allSatisfy({ $0 * 1000 > thresholds.p99LatencyWarnMs }) {
            alerts.append(.p99LatencyWarning(recentP99.values.max() ?? 0))
        }

        let recentErrorRate = errorRateHistory.filter {
            Date().timeIntervalSince($0.key) <= Double(thresholds.errorRateTripDurationMinutes * 60)
        }

        if let maxRate = recentErrorRate.values.max(), maxRate * 100 > thresholds.errorRateTripPercent {
            alerts.append(.errorRateTrip(maxRate * 100))
        }

        return alerts
    }

    private func cleanupOldHistory() {
        let cutoff = Date().addingTimeInterval(-3600)
        p99LatencyHistory = p99LatencyHistory.filter { $0.key > cutoff }
        errorRateHistory = errorRateHistory.filter { $0.key > cutoff }
    }
}

public enum SLOViolation {
    case latency(Double, Double)
    case errorRate(Double, Double)
    case backlog(Int, Int)
    case drift(Double, Double, Double, Double)
}

public enum Alert {
    case p99LatencyWarning(TimeInterval)
    case errorRateTrip(Double)
    case driftPage(Double, Double)
}
