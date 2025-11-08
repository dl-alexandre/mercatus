import Foundation

public struct TUIValidation {
    public static func validateMetrics(_ metrics: MetricsSnapshot) -> [String] {
        var errors: [String] = []

        // CI Gates
        if let p95 = metrics.bytesPerFrameP95, p95 > 6144 {
            errors.append("bytes/frame P95 (\(p95)) > 6 KiB threshold")
        }

        if metrics.widthCacheHitRate < 0.85 {
            errors.append("widthcache.hit_rate (\(String(format: "%.2f", metrics.widthCacheHitRate * 100))%) < 85% threshold")
        }

        if metrics.tailFastPathHitRate < 0.70 {
            errors.append("diff.tail_fastpath.hit_rate (\(String(format: "%.2f", metrics.tailFastPathHitRate * 100))%) < 70% threshold")
        }

        // Calculate painted nodes ratio (if we have total nodes)
        // This would need to be tracked separately
        // For now, we'll validate what we can

        return errors
    }

    public static func validateGoldenText(env: TerminalEnv) -> [String] {
        return TUIGoldenTextTests.validateGraphemeWidths(env: env)
    }

    public static func runAllValidations(env: TerminalEnv) async -> ValidationReport {
        let metrics = await TUIMetrics.shared.getMetrics()
        let metricErrors = validateMetrics(metrics)
        let goldenErrors = validateGoldenText(env: env)

        return ValidationReport(
            metricsErrors: metricErrors,
            goldenTextErrors: goldenErrors,
            passed: metricErrors.isEmpty && goldenErrors.isEmpty
        )
    }
}

public struct ValidationReport: Sendable {
    public let metricsErrors: [String]
    public let goldenTextErrors: [String]
    public let passed: Bool

    public func format() -> String {
        var lines: [String] = []
        lines.append("TUI Validation Report:")
        lines.append("  Status: \(passed ? "PASSED" : "FAILED")")

        if !metricsErrors.isEmpty {
            lines.append("  Metrics Errors:")
            for error in metricsErrors {
                lines.append("    - \(error)")
            }
        }

        if !goldenTextErrors.isEmpty {
            lines.append("  Golden Text Errors:")
            for error in goldenTextErrors {
                lines.append("    - \(error)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
