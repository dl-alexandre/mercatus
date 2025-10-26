import Foundation
import Utils

public class MetricsCollector {
    private let logger: StructuredLogger
    private var metrics: [String: MetricValue] = [:]
    private let lock = NSLock()

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    // MARK: - Prediction Metrics

    public func recordPredictionLatency(_ latency: TimeInterval, modelType: String) {
        let key = "prediction_latency_\(modelType.lowercased())"
        recordMetric(key: key, value: latency, type: .histogram)
    }

    public func recordPredictionAccuracy(_ accuracy: Double, modelType: String) {
        let key = "prediction_accuracy_\(modelType.lowercased())"
        recordMetric(key: key, value: accuracy, type: .gauge)
    }

    public func recordPredictionConfidence(_ confidence: Double, modelType: String) {
        let key = "prediction_confidence_\(modelType.lowercased())"
        recordMetric(key: key, value: confidence, type: .histogram)
    }

    public func recordPredictionCount(modelType: String) {
        let key = "prediction_count_\(modelType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    public func recordLowConfidencePrediction(modelType: String) {
        let key = "low_confidence_predictions_\(modelType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    // MARK: - Pattern Detection Metrics

    public func recordPatternDetectionLatency(_ latency: TimeInterval, patternType: String) {
        let key = "pattern_detection_latency_\(patternType.lowercased())"
        recordMetric(key: key, value: latency, type: .histogram)
    }

    public func recordPatternCount(patternType: String) {
        let key = "pattern_count_\(patternType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    public func recordPatternConfidence(_ confidence: Double, patternType: String) {
        let key = "pattern_confidence_\(patternType.lowercased())"
        recordMetric(key: key, value: confidence, type: .histogram)
    }

    // MARK: - API Metrics

    public func recordAPIRequest(endpoint: String, statusCode: Int, latency: TimeInterval) {
        let key = "api_requests_\(endpoint.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)

        let latencyKey = "api_latency_\(endpoint.lowercased())"
        recordMetric(key: latencyKey, value: latency, type: .histogram)

        let statusKey = "api_status_\(endpoint.lowercased())_\(statusCode)"
        recordMetric(key: statusKey, value: 1.0, type: .counter)
    }

    public func recordAPIError(endpoint: String, errorType: String) {
        let key = "api_errors_\(endpoint.lowercased())_\(errorType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    // MARK: - WebSocket Metrics

    public func recordWebSocketConnection() {
        recordMetric(key: "websocket_connections", value: 1.0, type: .counter)
    }

    public func recordWebSocketDisconnection() {
        recordMetric(key: "websocket_disconnections", value: 1.0, type: .counter)
    }

    public func recordWebSocketMessage(type: String) {
        let key = "websocket_messages_\(type.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    // MARK: - Cache Metrics

    public func recordCacheHit() {
        recordMetric(key: "cache_hits", value: 1.0, type: .counter)
    }

    public func recordCacheMiss() {
        recordMetric(key: "cache_misses", value: 1.0, type: .counter)
    }

    public func recordCacheSize(_ size: Int) {
        recordMetric(key: "cache_size", value: Double(size), type: .gauge)
    }

    // MARK: - Model Metrics

    public func recordModelDeployment(modelId: String, modelType: String) {
        let key = "model_deployments_\(modelType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    public func recordModelAccuracy(_ accuracy: Double, modelId: String) {
        let key = "model_accuracy_\(modelId)"
        recordMetric(key: key, value: accuracy, type: .gauge)
    }

    public func recordModelDrift(_ driftScore: Double, modelId: String) {
        let key = "model_drift_\(modelId)"
        recordMetric(key: key, value: driftScore, type: .gauge)
    }

    // MARK: - System Metrics

    public func recordMemoryUsage(_ usage: Int64) {
        recordMetric(key: "memory_usage_bytes", value: Double(usage), type: .gauge)
    }

    public func recordCPUUsage(_ usage: Double) {
        recordMetric(key: "cpu_usage_percent", value: usage, type: .gauge)
    }

    public func recordActiveConnections(_ count: Int) {
        recordMetric(key: "active_connections", value: Double(count), type: .gauge)
    }

    // MARK: - Data Quality Metrics

    public func recordDataQualityScore(_ score: Double, source: String) {
        let key = "data_quality_score_\(source.lowercased())"
        recordMetric(key: key, value: score, type: .gauge)
    }

    public func recordDataQualityIssue(issueType: String, source: String) {
        let key = "data_quality_issues_\(source.lowercased())_\(issueType.lowercased())"
        recordMetric(key: key, value: 1.0, type: .counter)
    }

    // MARK: - Private Methods

    private func recordMetric(key: String, value: Double, type: MetricType) {
        lock.lock()
        defer { lock.unlock() }

        let timestamp = Date()
        let metricValue = MetricValue(value: value, timestamp: timestamp, type: type)

        if var existing = metrics[key] {
            existing.addValue(value, timestamp: timestamp)
            metrics[key] = existing
        } else {
            metrics[key] = metricValue
        }
    }

    // MARK: - Public Access Methods

    public func getMetrics() -> [String: MetricValue] {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    public func getMetric(key: String) -> MetricValue? {
        lock.lock()
        defer { lock.unlock() }
        return metrics[key]
    }

    public func getMetricsSummary() -> MetricsSummary {
        lock.lock()
        defer { lock.unlock() }

        var summary = MetricsSummary()

        for (key, metric) in metrics {
            if key.contains("prediction_latency") {
                summary.predictionLatencyP95 = max(summary.predictionLatencyP95, metric.percentile(0.95))
            } else if key.contains("prediction_accuracy") {
                summary.averageAccuracy = (summary.averageAccuracy + metric.average) / 2.0
            } else if key.contains("api_requests") {
                summary.totalAPIRequests += Int(metric.sum)
            } else if key.contains("cache_hits") {
                summary.cacheHits += Int(metric.sum)
            } else if key.contains("cache_misses") {
                summary.cacheMisses += Int(metric.sum)
            }
        }

        if summary.cacheHits + summary.cacheMisses > 0 {
            summary.cacheHitRate = Double(summary.cacheHits) / Double(summary.cacheHits + summary.cacheMisses)
        }

        return summary
    }
}

// MARK: - Supporting Types

public struct MetricValue {
    public let type: MetricType
    private var values: [Double] = []
    private var timestamps: [Date] = []
    public let createdAt: Date

    public init(value: Double, timestamp: Date, type: MetricType) {
        self.type = type
        self.createdAt = timestamp
        addValue(value, timestamp: timestamp)
    }

    public mutating func addValue(_ value: Double, timestamp: Date) {
        values.append(value)
        timestamps.append(timestamp)

        // Keep only last 1000 values to prevent memory issues
        if values.count > 1000 {
            values.removeFirst()
            timestamps.removeFirst()
        }
    }

    public var count: Int {
        return values.count
    }

    public var sum: Double {
        return values.reduce(0, +)
    }

    public var average: Double {
        guard !values.isEmpty else { return 0.0 }
        return sum / Double(values.count)
    }

    public var min: Double {
        return values.min() ?? 0.0
    }

    public var max: Double {
        return values.max() ?? 0.0
    }

    public func percentile(_ p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        guard p.isFinite && p >= 0.0 && p <= 1.0 else { return 0.0 }
        let sortedValues = values.sorted()
        let index = Int(Double(sortedValues.count - 1) * p)
        return sortedValues[Swift.max(0, Swift.min(index, sortedValues.count - 1))]
    }
}

public enum MetricType {
    case counter
    case gauge
    case histogram
}

public struct MetricsSummary {
    public var predictionLatencyP95: Double = 0.0
    public var averageAccuracy: Double = 0.0
    public var totalAPIRequests: Int = 0
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0
    public var cacheHitRate: Double = 0.0
    public var timestamp: Date = Date()

    public init() {}
}
