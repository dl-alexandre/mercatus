import Foundation
import ArgumentParser
import SmartVestor
import Utils

#if os(macOS) || os(Linux)
import Darwin
#endif

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop running automation and release lock"
    )

    func run() async throws {
        let logger = StructuredLogger()
        logger.info(component: "StopCommand", event: "Stopping automation")

        let stateManager = AutomationStateManager(logger: logger)
        let lockManager = ProcessLockManager(logger: logger)

        // Load current state
        guard let state = try stateManager.load(), state.isRunning else {
            print("Automation is not currently running")

            // Still try to clean up stale lock file
            if lockManager.isLocked() {
                print("Cleaning up stale lock file...")
                try? lockManager.releaseLock()
            }

            return
        }

        // Check if PID is still running
        if let pid = state.pid {
            #if os(macOS) || os(Linux)
            let isRunning = kill(pid, 0) == 0 || errno == EPERM
            if isRunning {
                print("Stopping automation (PID: \(pid))...")

                // Send SIGTERM for graceful shutdown
                kill(pid, SIGTERM)

                // Wait up to 10 seconds for graceful shutdown
                for _ in 0..<10 {
                    let stillRunning = kill(pid, 0) == 0 || errno == EPERM
                    if !stillRunning {
                        break
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }

                // Force kill if still running
                if kill(pid, 0) == 0 || errno == EPERM {
                    print("Warning: Process did not stop gracefully, sending SIGKILL...")
                    kill(pid, SIGKILL)
                }
            } else {
                print("Process (PID: \(pid)) is not running")
            }
            #else
            print("Stop is not supported on this platform.")
            #endif
        }

        // Update state
        try stateManager.save(AutomationState(
            isRunning: false,
            mode: state.mode,
            startedAt: state.startedAt,
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            pid: nil
        ))

        // Release lock
        try lockManager.releaseLock()

        logger.info(component: "StopCommand", event: "Automation stopped successfully")
        print("Automation stopped")
    }
}
