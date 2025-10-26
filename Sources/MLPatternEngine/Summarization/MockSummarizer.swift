import Foundation
import Utils

public class MockSummarizer: SummarizationServiceProtocol {
    private let logger: StructuredLogger
    private let delay: TimeInterval

    public init(logger: StructuredLogger, delay: TimeInterval = 0.1) {
        self.logger = logger
        self.delay = delay
    }

    public func summarize<T>(_ content: T, summaryType: SummaryType) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let contentString = convertToString(content)
        let summary = generateMockSummary(content: contentString, summaryType: summaryType)

        logger.info(component: "MockSummarizer", event: "Content summarized", data: [
            "summary_type": summaryType.stringValue,
            "original_length": String(contentString.count),
            "summary_length": String(summary.count)
        ])

        return summary
    }

    private func generateMockSummary(content: String, summaryType: SummaryType) -> String {
        let length = min(200, content.count / 5)
        let prefix = content.prefix(length)

        switch summaryType {
        case .executive:
            return "[MOCK EXECUTIVE SUMMARY] \(prefix)..."
        case .detailed:
            return "[MOCK DETAILED SUMMARY] \(content.prefix(length * 2))..."
        case .technical:
            return "[MOCK TECHNICAL SUMMARY] Key metrics extracted from data."
        case .markdown:
            return """
            # Mock Summary

            ## Overview
            \(prefix)...

            ## Details
            Content processed using mock summarization.
            """
        }
    }

    private func convertToString<T>(_ content: T) -> String {
        if let string = content as? String {
            return string
        } else if let codable = content as? any Codable {
            if let data = try? JSONEncoder().encode(codable),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return String(describing: content)
    }
}
