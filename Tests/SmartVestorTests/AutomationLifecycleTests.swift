import Testing
import Foundation
@testable import SmartVestor
import Utils
import Darwin

@Suite
struct AutomationLifecycleTests {
    @Test
    func processLockPreventsConcurrentRuns() async throws {
        let tmpDir = NSTemporaryDirectory()
        let lockPath = (tmpDir as NSString).appendingPathComponent("sv-test.lock")
        // Ensure clean
        try? FileManager.default.removeItem(atPath: lockPath)
        let logger = StructuredLogger()
        let lock1 = ProcessLockManager(lockPath: lockPath, logger: logger)
        let lock2 = ProcessLockManager(lockPath: lockPath, logger: logger)

        let acquiredFirst = try lock1.acquireLock()
        #expect(acquiredFirst == true)
        let acquiredSecond = try lock2.acquireLock()
        #expect(acquiredSecond == false)

        try lock1.releaseLock()
        // After release, can acquire again
        let acquiredAfterRelease = try lock2.acquireLock()
        #expect(acquiredAfterRelease == true)
        try lock2.releaseLock()
    }

    @Test
    func automationStatePersistsAndClears() async throws {
        let tmpDir = NSTemporaryDirectory()
        let statePath = (tmpDir as NSString).appendingPathComponent("sv-state.json")
        try? FileManager.default.removeItem(atPath: statePath)
        let logger = StructuredLogger()
        let manager = AutomationStateManager(statePath: statePath, logger: logger)

        let state = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: 1234
        )
        try manager.save(state)
        let loaded = try manager.load()
        #expect(loaded != nil)
        #expect(loaded?.isRunning == true)
        #expect(loaded?.mode == .continuous)
        #expect(loaded?.pid == 1234)

        try manager.clear()
        let cleared = try manager.load()
        #expect(cleared == nil)
    }

    @Test
    func retryHandlerBacksOffAndEventuallySucceeds() async throws {
        let logger = StructuredLogger()
        let retry = RetryHandler(logger: logger)
        let start = Date()
        actor AttemptCounter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }
        let attempts = AttemptCounter()
        let result: Int = try await retry.execute(maxAttempts: 3, initialDelay: 0.05, maxDelay: 0.2, multiplier: 2.0) { @Sendable in
            await attempts.increment()
            let currentAttempts = await attempts.get()
            if currentAttempts < 3 {
                struct Transient: Error {}
                throw Transient()
            }
            return 42
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(result == 42)
        let finalAttempts = await attempts.get()
        #expect(finalAttempts == 3)
        // Should have waited at least ~0.05 + 0.1 ~= 0.15s before success on third attempt
        #expect(elapsed >= 0.14)
    }
}
