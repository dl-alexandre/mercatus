import Foundation
import Utils

public class SummarizationIntegration {
    private let summarizer: SummarizationServiceProtocol
    private let logger: StructuredLogger

    public init(summarizer: SummarizationServiceProtocol, logger: StructuredLogger) {
        self.summarizer = summarizer
        self.logger = logger
    }

    public func summarizeContent<T>(_ content: T, summaryType: SummaryType) async throws -> String {
        let summary = try await summarizer.summarize(content, summaryType: summaryType)

        logger.info(component: "SummarizationIntegration", event: "Content summarized", data: [
            "summary_type": summaryType.stringValue,
            "summary_length": String(summary.count)
        ])

        return summary
    }
}
