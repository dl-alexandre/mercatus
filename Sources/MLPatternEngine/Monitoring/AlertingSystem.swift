import Foundation
import Utils

public class AlertingSystem {
    private let metricsCollector: MetricsCollector
    private let logger: StructuredLogger
    private var alertRules: [AlertRule] = []
    private var activeAlerts: [String: Alert] = [:]
    private let lock = NSLock()

    public init(metricsCollector: MetricsCollector, logger: StructuredLogger) {
        self.metricsCollector = metricsCollector
        self.logger = logger
        setupDefaultAlertRules()
    }

    // MARK: - Alert Rule Management

    public func addAlertRule(_ rule: AlertRule) {
        lock.lock()
        defer { lock.unlock() }
        alertRules.append(rule)
    }

    public func removeAlertRule(_ ruleId: String) {
        lock.lock()
        defer { lock.unlock() }
        alertRules.removeAll { $0.id == ruleId }
    }

    public func getActiveAlerts() -> [Alert] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeAlerts.values)
    }

    public func getAlertHistory(limit: Int) -> [Alert] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeAlerts.values).prefix(limit).map { $0 }
    }

    public func getAlertRules() -> [AlertRule] {
        lock.lock()
        defer { lock.unlock() }
        return alertRules
    }

    // MARK: - Alert Evaluation

    public func evaluateAlerts() async {
        let metrics = metricsCollector.getMetrics()

        for rule in alertRules {
            await evaluateRule(rule, metrics: metrics)
        }
    }

    private func evaluateRule(_ rule: AlertRule, metrics: [String: MetricValue]) async {
        // For now, we'll skip evaluation since the new AlertRule structure
        // uses string conditions instead of the AlertCondition enum
        // This would need to be implemented with a proper condition parser
        return
    }

    private func evaluateCondition(metric: MetricValue, condition: AlertCondition) -> Bool {
        switch condition {
        case .greaterThan(let threshold):
            return metric.average > threshold
        case .lessThan(let threshold):
            return metric.average < threshold
        case .equals(let value):
            return abs(metric.average - value) < 0.001
        case .percentileGreaterThan(let percentile, let threshold):
            return metric.percentile(percentile) > threshold
        case .percentileLessThan(let percentile, let threshold):
            return metric.percentile(percentile) < threshold
        case .rateGreaterThan(let threshold):
            return Double(metric.count) > threshold
        case .rateLessThan(let threshold):
            return Double(metric.count) < threshold
        }
    }

    private func triggerAlert(rule: AlertRule, metric: MetricValue) async {

        let alertId = "\(rule.id)_\(Date().timeIntervalSince1970)"

        if activeAlerts[rule.id] == nil {
            let alert = Alert(
                id: alertId,
                severity: rule.severity,
                title: rule.name,
                message: rule.name,
                source: "AlertingSystem",
                timestamp: Date(),
                acknowledged: false,
                resolved: false
            )

            activeAlerts[rule.id] = alert

            logger.warn(component: "AlertingSystem", event: "Alert triggered", data: [
                "alertId": alertId,
                "ruleId": rule.id,
                "severity": rule.severity.rawValue,
                "message": rule.name
            ])

            await sendAlertNotification(alert)
        }
    }

    private func resolveAlert(ruleId: String) async {

        if let alert = activeAlerts[ruleId] {
            logger.info(component: "AlertingSystem", event: "Alert resolved", data: [
                "alertId": alert.id,
                "ruleId": ruleId
            ])

            activeAlerts.removeValue(forKey: ruleId)
        }
    }


    // MARK: - Notification System

    private func sendAlertNotification(_ alert: Alert) async {
        // In a real implementation, this would send notifications via:
        // - Email
        // - Slack
        // - PagerDuty
        // - Webhook

        logger.error(component: "AlertingSystem", event: "ALERT: \(alert.message)", data: [
            "alertId": alert.id,
            "severity": alert.severity.rawValue,
            "title": alert.title,
            "source": alert.source
        ])
    }

    // MARK: - Default Alert Rules

    private func setupDefaultAlertRules() {
        // Latency alerts
        addAlertRule(AlertRule(
            id: "high_prediction_latency",
            name: "High Prediction Latency",
            condition: "percentileGreaterThan(0.95, 0.15)",
            severity: .warning,
            enabled: true,
            cooldown: 300
        ))

        // Accuracy alerts
        addAlertRule(AlertRule(
            id: "low_prediction_accuracy",
            name: "Low Prediction Accuracy",
            condition: "lessThan(0.70)",
            severity: .critical,
            enabled: true,
            cooldown: 600
        ))

        // Error rate alerts
        addAlertRule(AlertRule(
            id: "high_error_rate",
            name: "High API Error Rate",
            condition: "rateGreaterThan(10)",
            severity: .warning,
            enabled: true,
            cooldown: 300
        ))

        // Cache performance alerts
        addAlertRule(AlertRule(
            id: "low_cache_hit_rate",
            name: "Low Cache Hit Rate",
            condition: "rateLessThan(50)",
            severity: .info,
            enabled: true,
            cooldown: 600
        ))

        // Model drift alerts
        addAlertRule(AlertRule(
            id: "model_drift_detected",
            name: "Model Drift Detected",
            condition: "greaterThan(0.25)",
            severity: .critical,
            enabled: true,
            cooldown: 1800
        ))

        // Memory usage alerts
        addAlertRule(AlertRule(
            id: "high_memory_usage",
            name: "High Memory Usage",
            condition: "greaterThan(2000000000)",
            severity: .warning,
            enabled: true,
            cooldown: 300
        ))

        // Data quality alerts
        addAlertRule(AlertRule(
            id: "low_data_quality",
            name: "Low Data Quality",
            condition: "lessThan(0.8)",
            severity: .info,
            enabled: true,
            cooldown: 600
        ))

        // Volatility alerts
        addAlertRule(AlertRule(
            id: "high_volatility_1h",
            name: "High Volatility 1H",
            condition: "percentileGreaterThan(0.95, 0.6)",
            severity: .warning,
            enabled: true,
            cooldown: 300
        ))

        addAlertRule(AlertRule(
            id: "high_volatility_4h",
            name: "High Volatility 4H",
            condition: "percentileGreaterThan(0.95, 0.8)",
            severity: .critical,
            enabled: true,
            cooldown: 600
        ))

        addAlertRule(AlertRule(
            id: "high_volatility_24h",
            name: "High Volatility 24H",
            condition: "percentileGreaterThan(0.95, 1.0)",
            severity: .critical,
            enabled: true,
            cooldown: 1800
        ))

        addAlertRule(AlertRule(
            id: "volatility_spike_detected",
            name: "Volatility Spike Detected",
            condition: "rateGreaterThan(5)",
            severity: .warning,
            enabled: true,
            cooldown: 300
        ))

        addAlertRule(AlertRule(
            id: "low_volatility_confidence",
            name: "Low Volatility Confidence",
            condition: "lessThan(0.5)",
            severity: .info,
            enabled: true,
            cooldown: 600
        ))
    }
}

// MARK: - Alert Models

public enum AlertCondition {
    case greaterThan(Double)
    case lessThan(Double)
    case equals(Double)
    case percentileGreaterThan(Double, Double) // percentile, threshold
    case percentileLessThan(Double, Double)
    case rateGreaterThan(Double) // count per minute
    case rateLessThan(Double)
}

public enum AlertState: String, CaseIterable {
    case active = "ACTIVE"
    case resolved = "RESOLVED"
    case acknowledged = "ACKNOWLEDGED"
}
