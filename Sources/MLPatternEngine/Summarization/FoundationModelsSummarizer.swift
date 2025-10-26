import Foundation
import Utils

public class FoundationModelsSummarizer: SummarizationServiceProtocol {
    private let logger: StructuredLogger
    private var isAvailable: Bool = false
    private var availabilityReason: String = "Not checked"

    public init(logger: StructuredLogger) {
        self.logger = logger
        initializeModel()
    }

    private func initializeModel() {
        isAvailable = false
        availabilityReason = "Foundation Models not available - using mock implementation"
        logger.warn(component: "FoundationModelsSummarizer", event: "Using mock summarization")
    }

    public func summarize<T>(_ content: T, summaryType: SummaryType) async throws -> String {
        let contentString = convertToString(content)
        let summary = """
        Summary (\(summaryType.stringValue)):
        \(String(contentString.prefix(200)))...
        """

        logger.info(component: "FoundationModelsSummarizer", event: "Content summarized", data: [
            "summary_type": summaryType.stringValue,
            "summary_length": String(summary.count)
        ])

        return summary
    }

    private func buildPromptText<T>(content: T, summaryType: SummaryType) -> String {
        let contentString = convertToString(content)

        let instructions: String
        switch summaryType {
        case .executive:
            instructions = "Provide a brief executive summary highlighting key points in one paragraph."
        case .detailed:
            instructions = "Provide a detailed summary with all important information."
        case .technical:
            instructions = "Provide a technical summary focusing on data patterns and metrics."
        case .markdown:
            instructions = "Provide a summary in markdown format with clear sections."
        }

        return """
        Summarization Task:
        \(instructions)

        Content to summarize:
        \(contentString)
        """
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

extension SummaryType {
    var stringValue: String {
        switch self {
        case .executive: return "executive"
        case .detailed: return "detailed"
        case .technical: return "technical"
        case .markdown: return "markdown"
        }
    }
}
