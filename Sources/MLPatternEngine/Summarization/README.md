# MLPatternEngine Summarization

On-device LLM summarization for Mercatus cryptocurrency analysis.

## Overview

The summarization module integrates Apple's Foundation Models framework to provide privacy-preserving on-device summarization for transaction histories, market data, audit logs, and other cryptocurrency analysis data.

## Components

- **SummarizationServiceProtocol**: Protocol defining summarization operations
- **FoundationModelsSummarizer**: Real implementation using Apple's on-device LLMs
- **MockSummarizer**: Mock implementation for testing
- **SummarizationIntegration**: Integration wrapper for the MLPatternEngine

## Usage

### Basic Usage

```swift
let logger = StructuredLogger(maxLogsPerMinute: 1000)
let summarizer = MockSummarizer(logger: logger)

let content = "Long text to summarize..."
let summary = try await summarizer.summarize(content, summaryType: .executive)
```

### Foundation Models (Production)

```swift
let summarizer = FoundationModelsSummarizer(logger: logger)
let summary = try await summarizer.summarize(content, summaryType: .executive)
```

### Integration Wrapper

```swift
let logger = StructuredLogger(maxLogsPerMinute: 1000)
let mockSummarizer = MockSummarizer(logger: logger)
let integration = SummarizationIntegration(summarizer: mockSummarizer, logger: logger)

let summary = try await integration.summarizeContent(content, summaryType: .technical)
```

## Summary Types

- **executive**: Brief summary highlighting key points
- **detailed**: Comprehensive summary with all information
- **technical**: Focus on data patterns and metrics
- **markdown**: Structured summary in markdown format

## Requirements

- **Foundation Models**: Requires macOS 15.0+ / iOS 18.0+ and Apple Silicon
- **Mock Summarizer**: Works on all platforms for testing
- Swift 6.0+

## Architecture

Follows protocol-oriented design with dependency injection:

```swift
public protocol SummarizationServiceProtocol {
    func summarize<T>(_ content: T, summaryType: SummaryType) async throws -> String
}
```

## Error Handling

```swift
do {
    let summary = try await summarizer.summarize(content, summaryType: .executive)
} catch SummarizationError.modelUnavailable {
    // Handle unavailable model
} catch SummarizationError.summarizationFailed(let reason) {
    // Handle summarization failure
} catch {
    // Handle other errors
}
```

## Privacy

Uses on-device LLM processing with private cloud compute fallback. No data leaves the device without user permission.

## Testing

```bash
swift test --filter SummarizationTests
```

Tests cover:
- Basic summarization functionality
- Different summary types
- Empty content handling
- Codable content support
- Integration wrapper
