import Testing
import MLPatternEngineSummarization
import Utils

@Suite("Summarization Tests")
struct SummarizationTests {

    @Test
    func mockSummarizerBasicFunctionality() async throws {
        let logger = StructuredLogger(maxLogsPerMinute: 1000)
        let summarizer = MockSummarizer(logger: logger, delay: 0.0)

        let testContent = """
        This is a long text that needs to be summarized.
        It contains multiple sentences with various information.
        The goal is to create a shorter version that captures the key points.
        Testing the summarization functionality.
        """

        let summary = try await summarizer.summarize(testContent, summaryType: .executive)

        #expect(!summary.isEmpty)
        #expect(summary.contains("MOCK"))
    }

    @Test
    func mockSummarizerDifferentSummaryTypes() async throws {
        let logger = StructuredLogger(maxLogsPerMinute: 1000)
        let summarizer = MockSummarizer(logger: logger, delay: 0.0)

        let testContent = "Testing content for summarization"

        let executiveSummary = try await summarizer.summarize(testContent, summaryType: .executive)
        let detailedSummary = try await summarizer.summarize(testContent, summaryType: .detailed)
        let technicalSummary = try await summarizer.summarize(testContent, summaryType: .technical)
        let markdownSummary = try await summarizer.summarize(testContent, summaryType: .markdown)

        #expect(executiveSummary.contains("EXECUTIVE"))
        #expect(detailedSummary.contains("DETAILED"))
        #expect(technicalSummary.contains("TECHNICAL"))
        #expect(markdownSummary.contains("#"))
    }

    @Test
    func mockSummarizerHandlesEmptyContent() async throws {
        let logger = StructuredLogger(maxLogsPerMinute: 1000)
        let summarizer = MockSummarizer(logger: logger, delay: 0.0)

        let emptyContent = ""
        let summary = try await summarizer.summarize(emptyContent, summaryType: .executive)

        #expect(!summary.isEmpty)
    }

    @Test
    func summarizationIntegrationProvidesConvenienceWrapper() async throws {
        let logger = StructuredLogger(maxLogsPerMinute: 1000)
        let mockSummarizer = MockSummarizer(logger: logger, delay: 0.0)
        let integration = SummarizationIntegration(summarizer: mockSummarizer, logger: logger)

        let testContent = "This is test content that needs summarizing."
        let summary = try await integration.summarizeContent(testContent, summaryType: .executive)

        #expect(!summary.isEmpty)
    }

    @Test
    func mockSummarizerHandlesCodableContent() async throws {
        let logger = StructuredLogger(maxLogsPerMinute: 1000)
        let summarizer = MockSummarizer(logger: logger, delay: 0.0)

        struct TestData: Codable {
            let name: String
            let value: Int
        }

        let testData = TestData(name: "test", value: 42)
        let summary = try await summarizer.summarize(testData, summaryType: .executive)

        #expect(!summary.isEmpty)
    }
}
