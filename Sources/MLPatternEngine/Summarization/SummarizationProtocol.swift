import Foundation
import Utils

public protocol SummarizationServiceProtocol {
    func summarize<T>(_ content: T, summaryType: SummaryType) async throws -> String
}

public enum SummaryType {
    case executive
    case detailed
    case technical
    case markdown
}

public enum SummarizationError: Error {
    case modelUnavailable
    case invalidInput
    case summarizationFailed(reason: String)
    case timeout
}

public struct SummarizationResult {
    public let originalLength: Int
    public let summaryLength: Int
    public let compressionRatio: Double
    public let summary: String
    public let metadata: [String: String]

    public init(
        originalLength: Int,
        summaryLength: Int,
        compressionRatio: Double,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.originalLength = originalLength
        self.summaryLength = summaryLength
        self.compressionRatio = compressionRatio
        self.summary = summary
        self.metadata = metadata
    }
}
