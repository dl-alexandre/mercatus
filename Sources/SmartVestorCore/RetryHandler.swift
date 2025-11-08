import Foundation
import Utils
import Core

public actor RetryHandler {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger = StructuredLogger()) {
        self.logger = logger
    }

    public func execute<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        multiplier: Double = 2.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                let result = try await operation()

                if attempt > 1 {
                    logger.info(component: "RetryHandler", event: "Operation succeeded after retry", data: [
                        "attempt": String(attempt),
                        "max_attempts": String(maxAttempts)
                    ])
                }

                return result

            } catch {
                lastError = error

                // Don't retry on permanent errors (auth, validation, etc.)
                if isPermanentError(error) {
                    logger.warn(component: "RetryHandler", event: "Permanent error, not retrying", data: [
                        "error": error.localizedDescription,
                        "attempt": String(attempt)
                    ])
                    throw error
                }

                // Last attempt - throw the error
                if attempt == maxAttempts {
                    logger.error(component: "RetryHandler", event: "All retry attempts exhausted", data: [
                        "max_attempts": String(maxAttempts),
                        "final_error": error.localizedDescription
                    ])
                    throw error
                }

                // Wait before retrying with exponential backoff
                let cappedDelay = min(delay, maxDelay)

                logger.warn(component: "RetryHandler", event: "Operation failed, retrying", data: [
                    "attempt": String(attempt),
                    "max_attempts": String(maxAttempts),
                    "delay_seconds": String(cappedDelay),
                    "error": error.localizedDescription
                ])

                try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))

                // Increase delay for next attempt
                delay *= multiplier
            }
        }

        // Should never reach here, but satisfy compiler
        if let error = lastError {
            throw error
        } else {
            throw SmartVestorError.executionError("Retry handler failed without error")
        }
    }

    private func isPermanentError(_ error: Error) -> Bool {
        // Check for permanent errors that shouldn't be retried
        if let arbError = error as? ArbitrageError {
            switch arbError {
            case .connection(.authenticationFailed):
                return true
            case .logic:
                return true
            case .data(.invalidFormat), .data(.invalidJSON):
                return true
            default:
                return false
            }
        }

        if let smartError = error as? SmartVestorError {
            switch smartError {
            case .validationError, .configurationError:
                return true
            default:
                return false
            }
        }

        // Network errors, timeouts, rate limits are transient
        return false
    }
}
