import Foundation
import Utils
import Core

public protocol CommandProcessorProtocol: Sendable {
    func process(_ command: TUICommand, currentState: AutomationState?) async throws -> CommandResult
}

public struct CommandResult: Sendable {
    public let success: Bool
    public let message: String?
    public let shouldExit: Bool

    public init(success: Bool, message: String? = nil, shouldExit: Bool = false) {
        self.success = success
        self.message = message
        self.shouldExit = shouldExit
    }
}

public final class CommandProcessor: CommandProcessorProtocol, @unchecked Sendable {
    private let stateManager: AutomationStateManager
    private let logger: StructuredLogger
    private let persistence: PersistenceProtocol?

    public init(
        stateManager: AutomationStateManager,
        logger: StructuredLogger = StructuredLogger(),
        persistence: PersistenceProtocol? = nil
    ) {
        self.stateManager = stateManager
        self.logger = logger
        self.persistence = persistence
    }

    public func process(_ command: TUICommand, currentState: AutomationState?) async throws -> CommandResult {
        switch command {
        case .pause:
        return try await handlePause(currentState: currentState)
        case .resume:
        return try await handleResume(currentState: currentState)
        case .logs:
        return try await handleLogs()
        case .start:
        return try await handleStart(currentState: currentState)
        case .quit:
        return CommandResult(success: true, message: "Exiting...", shouldExit: true)
        case .help:
            return CommandResult(success: true, message: "Help displayed", shouldExit: false)
        case .refresh:
            return CommandResult(success: true, message: "Display refreshed", shouldExit: false)
        }
    }

    private func handlePause(currentState: AutomationState?) async throws -> CommandResult {
        guard let state = currentState else {
            return CommandResult(success: false, message: "No automation state available")
        }

        guard state.isRunning else {
            return CommandResult(success: false, message: "Automation is already paused")
        }

        let pausedState = AutomationState(
            isRunning: false,
            mode: state.mode,
            startedAt: state.startedAt,
            lastExecutionTime: Date(),
            nextExecutionTime: state.nextExecutionTime,
            pid: state.pid
        )

        try stateManager.save(pausedState)

        logger.info(component: "CommandProcessor", event: "Automation paused", data: [
            "mode": state.mode.rawValue
        ])

        return CommandResult(success: true, message: "Automation paused")
    }

    private func handleResume(currentState: AutomationState?) async throws -> CommandResult {
        guard let state = currentState else {
            return CommandResult(success: false, message: "No automation state available")
        }

        guard !state.isRunning else {
            return CommandResult(success: false, message: "Automation is already running")
        }

        let resumedState = AutomationState(
            isRunning: true,
            mode: state.mode,
            startedAt: state.startedAt ?? Date(),
            lastExecutionTime: state.lastExecutionTime,
            nextExecutionTime: state.nextExecutionTime,
            pid: state.pid
        )

        try stateManager.save(resumedState)

        logger.info(component: "CommandProcessor", event: "Automation resumed", data: [
            "mode": state.mode.rawValue
        ])

        return CommandResult(success: true, message: "Automation resumed")
    }

    private func handleLogs() async throws -> CommandResult {
        var logLines: [String] = []

        if let persistence = persistence {
            do {
                // Use a very small limit to avoid memory issues with large tables
                let transactions = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 5)

                logLines.append("=== Recent Transactions ===")
                if transactions.isEmpty {
                    logLines.append("No recent transactions")
                } else {
                    logLines.append("Showing \(transactions.count) most recent:")
                    for tx in transactions {
                        let dateFormatter = ISO8601DateFormatter()
                        dateFormatter.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]
                        let dateStr = dateFormatter.string(from: tx.timestamp)
                        logLines.append("[\(dateStr)] \(tx.type.rawValue.uppercased()) \(tx.asset) qty=\(String(format: "%.6f", tx.quantity)) @ \(String(format: "%.6f", tx.price)) ex=\(tx.exchange)")
                    }
                }
            } catch {
                let errorMsg = error.localizedDescription
                logLines.append("Error loading transactions: \(errorMsg)")

                if errorMsg.contains("out of memory") || errorMsg.contains("SQLITE_NOMEM") {
                    logLines.append("")
                    logLines.append("⚠️  Database has too many transactions.")
                    logLines.append("   Consider cleaning up old transactions:")
                    logLines.append("   sqlite3 smartvestor.db \"DELETE FROM tx WHERE ts < (SELECT ts FROM tx ORDER BY ts DESC LIMIT 1 OFFSET 10000);\"")
                    logLines.append("")
                    logLines.append("   Or use VACUUM to reclaim space:")
                    logLines.append("   sqlite3 smartvestor.db \"VACUUM;\"")
                } else if errorMsg.contains("Failed to prepare statement") {
                    logLines.append("")
                    logLines.append("⚠️  Database query failed. This may indicate:")
                    logLines.append("   - Database corruption")
                    logLines.append("   - Insufficient memory")
                    logLines.append("   - Too many concurrent connections")
                    logLines.append("   Try: sqlite3 smartvestor.db \"PRAGMA integrity_check;\"")
                }
            }
        }

        logLines.append("")
        logLines.append("=== System Logs ===")

        #if os(macOS) || os(Linux)
        let logPaths = [
            "/tmp/smartvestor.log",
            "smartvestor.log",
            ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"] ?? ""
        ].filter { !$0.isEmpty }

        for logPath in logPaths {
            if let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) {
                let lines = logContent.components(separatedBy: .newlines).suffix(20)
                logLines.append("--- \(logPath) (last 20 lines) ---")
                logLines.append(contentsOf: lines)
                break
            }
        }
        #endif

        logLines.append("")
        logLines.append("(Press any key to return)")

        let message = logLines.joined(separator: "\n")

        return CommandResult(success: true, message: message)
    }

    private func handleStart(currentState: AutomationState?) async throws -> CommandResult {
        let lockManager = ProcessLockManager(logger: logger)

        if let lockPid = lockManager.getLockPid() {
            return CommandResult(success: false, message: "Service already running (PID: \(lockPid)). Use 'sv stop' first.")
        }

        guard try lockManager.acquireLock() else {
            return CommandResult(success: false, message: "Lock file exists. Use 'sv stop' to clean up.")
        }

        let executablePath = ProcessInfo.processInfo.arguments.first ?? "sv"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        #if os(macOS) || os(Linux)
        var args = [executablePath, "start"]
        if let mode = currentState?.mode {
            args.append("--mode")
            args.append(mode.rawValue)
        }

        process.arguments = args
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()

            try? lockManager.releaseLock()

            logger.info(component: "CommandProcessor", event: "Service started from TUI", data: [
                "pid": String(process.processIdentifier)
            ])

            try? await Task.sleep(nanoseconds: 500_000_000)

            let updatedState = try? stateManager.load()
            if let state = updatedState, state.isRunning {
                return CommandResult(success: true, message: "Service started (PID: \(state.pid ?? 0))\n(Press 'r' to refresh status)")
            } else {
                return CommandResult(success: true, message: "Service starting in background (PID: \(process.processIdentifier))\n(Press 'r' to refresh status)")
            }
        } catch {
            try? lockManager.releaseLock()
            logger.error(component: "CommandProcessor", event: "Failed to start service", data: [
                "error": error.localizedDescription
            ])
            return CommandResult(success: false, message: "Failed to start service: \(error.localizedDescription)")
        }
        #else
        return CommandResult(success: false, message: "Starting service from TUI not supported on this platform")
        #endif
    }
}
