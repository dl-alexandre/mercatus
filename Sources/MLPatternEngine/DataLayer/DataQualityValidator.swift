import Foundation
import Utils

public class DataQualityValidator: DataQualityValidatorProtocol {
    private let clockSkewTolerance: TimeInterval = 5.0
    private let outlierThreshold: Double = 3.0
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func validateDataPoint(_ dataPoint: MarketDataPoint) -> DataQualityResult {
        var issues: [DataQualityIssue] = []

        let timestampIssue = validateTimestamp(dataPoint.timestamp)
        if let issue = timestampIssue {
            issues.append(issue)
        }

        let priceIssues = validatePrices(dataPoint)
        issues.append(contentsOf: priceIssues)

        let volumeIssue = validateVolume(dataPoint.volume)
        if let issue = volumeIssue {
            issues.append(issue)
        }

        let qualityScore = calculateQualityScore([dataPoint])

        // Data is invalid if it has any critical issues (like zero prices)
        let isValid = issues.isEmpty || issues.allSatisfy { $0.severity != .critical }

        return DataQualityResult(
            isValid: isValid,
            qualityScore: qualityScore,
            issues: issues
        )
    }

    public func validateDataBatch(_ dataPoints: [MarketDataPoint]) -> DataQualityResult {
        var allIssues: [DataQualityIssue] = []

        for dataPoint in dataPoints {
            let result = validateDataPoint(dataPoint)
            allIssues.append(contentsOf: result.issues)
        }

        let duplicateIssues = detectDuplicates(dataPoints)
        allIssues.append(contentsOf: duplicateIssues)

        let qualityScore = calculateQualityScore(dataPoints)

        return DataQualityResult(
            isValid: allIssues.isEmpty || allIssues.allSatisfy { $0.severity != .critical },
            qualityScore: qualityScore,
            issues: allIssues
        )
    }

    public func calculateQualityScore(_ dataPoints: [MarketDataPoint]) -> Double {
        guard !dataPoints.isEmpty else { return 0.0 }

        let result = validateDataBatch(dataPoints)
        let criticalIssues = result.issues.filter { $0.severity == .critical }.count
        let highIssues = result.issues.filter { $0.severity == .high }.count
        let mediumIssues = result.issues.filter { $0.severity == .medium }.count
        let lowIssues = result.issues.filter { $0.severity == .low }.count

        let totalPenalty = Double(criticalIssues * 10 + highIssues * 5 + mediumIssues * 2 + lowIssues)
        let maxPenalty = Double(dataPoints.count * 10)

        return max(0.0, 1.0 - (totalPenalty / maxPenalty))
    }

    private func validateTimestamp(_ timestamp: Date) -> DataQualityIssue? {
        let now = Date()
        let timeDiff = abs(now.timeIntervalSince(timestamp))

        if timeDiff > clockSkewTolerance {
            return DataQualityIssue(
                type: .clockSkew,
                severity: .high,
                message: "Timestamp is \(timeDiff) seconds away from current time",
                timestamp: timestamp
            )
        }

        return nil
    }

    private func validatePrices(_ dataPoint: MarketDataPoint) -> [DataQualityIssue] {
        var issues: [DataQualityIssue] = []

        // Check for zero or negative prices
        if dataPoint.open <= 0 {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "Open price is zero or negative: \(dataPoint.open)",
                timestamp: dataPoint.timestamp
            ))
        }

        if dataPoint.high <= 0 {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "High price is zero or negative: \(dataPoint.high)",
                timestamp: dataPoint.timestamp
            ))
        }

        if dataPoint.low <= 0 {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "Low price is zero or negative: \(dataPoint.low)",
                timestamp: dataPoint.timestamp
            ))
        }

        if dataPoint.close <= 0 {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "Close price is zero or negative: \(dataPoint.close)",
                timestamp: dataPoint.timestamp
            ))
        }

        // Check price relationships
        if dataPoint.high < dataPoint.low {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "High price (\(dataPoint.high)) is less than low price (\(dataPoint.low))",
                timestamp: dataPoint.timestamp
            ))
        }

        if dataPoint.high < dataPoint.open || dataPoint.high < dataPoint.close {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .high,
                message: "High price (\(dataPoint.high)) is less than open (\(dataPoint.open)) or close (\(dataPoint.close))",
                timestamp: dataPoint.timestamp
            ))
        }

        if dataPoint.low > dataPoint.open || dataPoint.low > dataPoint.close {
            issues.append(DataQualityIssue(
                type: .outlier,
                severity: .high,
                message: "Low price (\(dataPoint.low)) is greater than open (\(dataPoint.open)) or close (\(dataPoint.close))",
                timestamp: dataPoint.timestamp
            ))
        }

        return issues
    }

    private func validateVolume(_ volume: Double) -> DataQualityIssue? {
        if volume < 0 {
            return DataQualityIssue(
                type: .outlier,
                severity: .critical,
                message: "Volume cannot be negative",
                timestamp: Date()
            )
        }

        return nil
    }

    private func detectDuplicates(_ dataPoints: [MarketDataPoint]) -> [DataQualityIssue] {
        var issues: [DataQualityIssue] = []
        var seenTimestamps: Set<Date> = []

        for dataPoint in dataPoints {
            if seenTimestamps.contains(dataPoint.timestamp) {
                issues.append(DataQualityIssue(
                    type: .duplicate,
                    severity: .medium,
                    message: "Duplicate timestamp detected",
                    timestamp: dataPoint.timestamp
                ))
            } else {
                seenTimestamps.insert(dataPoint.timestamp)
            }
        }

        return issues
    }
}
