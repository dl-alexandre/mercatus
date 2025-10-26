import Foundation

public protocol DataIngestionProtocol {
    func startIngestion() async throws
    func stopIngestion() async throws
    func getLatestData(for symbol: String, limit: Int) async throws -> [MarketDataPoint]
    func getHistoricalData(for symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint]
    func subscribeToRealTimeData(for symbols: [String], callback: @escaping (MarketDataPoint) -> Void) async throws
}

public protocol DataQualityValidatorProtocol {
    func validateDataPoint(_ dataPoint: MarketDataPoint) -> DataQualityResult
    func validateDataBatch(_ dataPoints: [MarketDataPoint]) -> DataQualityResult
    func calculateQualityScore(_ dataPoints: [MarketDataPoint]) -> Double
}

public struct DataQualityResult {
    public let isValid: Bool
    public let qualityScore: Double
    public let issues: [DataQualityIssue]

    public init(isValid: Bool, qualityScore: Double, issues: [DataQualityIssue]) {
        self.isValid = isValid
        self.qualityScore = qualityScore
        self.issues = issues
    }
}

public struct DataQualityIssue {
    public let type: IssueType
    public let severity: Severity
    public let message: String
    public let timestamp: Date

    public enum IssueType: String, CaseIterable {
        case missingData = "MISSING_DATA"
        case outlier = "OUTLIER"
        case clockSkew = "CLOCK_SKEW"
        case duplicate = "DUPLICATE"
        case incomplete = "INCOMPLETE"
    }

    public enum Severity: String, CaseIterable {
        case low = "LOW"
        case medium = "MEDIUM"
        case high = "HIGH"
        case critical = "CRITICAL"
    }

    public init(type: IssueType, severity: Severity, message: String, timestamp: Date) {
        self.type = type
        self.severity = severity
        self.message = message
        self.timestamp = timestamp
    }
}
