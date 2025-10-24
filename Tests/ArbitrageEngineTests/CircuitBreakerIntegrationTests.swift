import Testing
import Foundation
@testable import Core
@testable import Utils
@testable import Connectors

@Suite("Circuit Breaker Integration Tests")
struct CircuitBreakerIntegrationTests {

    @Test("BaseExchangeConnector uses circuit breaker to prevent connections")
    func baseExchangeConnectorUsesCircuitBreaker() async throws {
        let logger = StructuredLogger()
        let attemptCounter = SyncAttemptCounter()

        let requestBuilder: BaseExchangeConnector.RequestBuilder = { [attemptCounter] _ in
            attemptCounter.increment()
            throw URLError(.networkConnectionLost)
        }

        let connector = BaseExchangeConnector(
            name: "TestExchange",
            logger: logger,
            backoffConfiguration: .init(initial: 1000.0, multiplier: 1.0, maxDelay: 1000.0),
            circuitBreakerConfiguration: .init(failureThreshold: 2, timeout: 60.0, successThreshold: 1),
            requestBuilder: requestBuilder
        )

        defer {
            Task { await connector.disconnect() }
        }

        let initialCount = attemptCounter.count

        for _ in 0..<2 {
            do {
                try await connector.connect()
            } catch {
            }
        }

        #expect(attemptCounter.count > initialCount)

        do {
            try await connector.connect()
            Issue.record("Expected circuit breaker to prevent connection")
        } catch let error as ArbitrageError {
            if case .connection(.circuitBreakerOpen) = error {
            } else {
                Issue.record("Expected circuit breaker error, got \(error)")
            }
        } catch {
            Issue.record("Expected ArbitrageError, got \(error)")
        }
    }

    @Test("Circuit breaker allows retry after timeout")
    func circuitBreakerAllowsRetryAfterTimeout() async throws {
        let timeProvider = SyncTimeProvider()

        let breaker = CircuitBreaker(
            configuration: .init(failureThreshold: 2, timeout: 5.0, successThreshold: 1),
            clock: { timeProvider.currentTime }
        )

        await breaker.recordFailure()
        await breaker.recordFailure()

        #expect(await breaker.canAttempt() == false)

        timeProvider.advance(by: 6.0)

        #expect(await breaker.canAttempt() == true)
        #expect(await breaker.currentState == CircuitBreaker.State.halfOpen)

        await breaker.recordSuccess()

        #expect(await breaker.currentState == CircuitBreaker.State.closed)
        #expect(await breaker.canAttempt() == true)
    }

    @Test("Multiple failures accumulate in circuit breaker")
    func multipleFailuresAccumulate() async {
        let breaker = CircuitBreaker(
            configuration: .init(failureThreshold: 5, timeout: 60.0, successThreshold: 2)
        )

        for _ in 1...4 {
            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == true)
        }

        await breaker.recordFailure()
        #expect(await breaker.canAttempt() == false)
        #expect(await breaker.currentState.failureCount == 5)
    }

    @Test("Circuit breaker tracks additional failures while open")
    func circuitBreakerTracksAdditionalFailuresWhileOpen() async {
        let breaker = CircuitBreaker(
            configuration: .init(failureThreshold: 3, timeout: 60.0, successThreshold: 1)
        )

        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()

        #expect(await breaker.canAttempt() == false)
        let initialCount = await breaker.currentState.failureCount
        #expect(initialCount == 3)

        await breaker.recordFailure()
        let updatedCount = await breaker.currentState.failureCount
        #expect(updatedCount == 4)
    }

    @Test("Success in closed state resets failure count")
    func successInClosedStateResetsFailureCount() async {
        let breaker = CircuitBreaker(
            configuration: .init(failureThreshold: 5, timeout: 60.0, successThreshold: 1)
        )

        await breaker.recordFailure()
        await breaker.recordFailure()
        #expect(await breaker.canAttempt() == true)

        await breaker.recordSuccess()

        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()
        #expect(await breaker.canAttempt() == true)
    }
}

actor AttemptCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

final class SyncAttemptCounter: @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

final class SyncTimeProvider: @unchecked Sendable {
    private var _currentTime = Date()
    private let lock = NSLock()

    var currentTime: Date {
        lock.lock()
        defer { lock.unlock() }
        return _currentTime
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _currentTime = _currentTime.addingTimeInterval(interval)
    }
}
