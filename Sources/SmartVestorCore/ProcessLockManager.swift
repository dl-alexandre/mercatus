import Foundation
import Utils

public class ProcessLockManager {
    private let lockPath: String
    private let logger: StructuredLogger

    public init(lockPath: String = ".automation.pid", logger: StructuredLogger = StructuredLogger()) {
        self.lockPath = lockPath
        self.logger = logger
    }

    public func acquireLock() throws -> Bool {
        // Check if PID file exists and process is still running
        if let existingPid = getExistingPid(), isProcessRunning(existingPid) {
            logger.warn(component: "ProcessLockManager", event: "Lock file exists and process is running", data: [
                "pid": String(existingPid),
                "lock_path": lockPath
            ])
            return false
        }

        // Remove stale lock file if process is not running
        if FileManager.default.fileExists(atPath: lockPath) {
            try FileManager.default.removeItem(atPath: lockPath)
            logger.info(component: "ProcessLockManager", event: "Removed stale lock file")
        }

        // Create new PID file
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let pidData = String(currentPid).data(using: .utf8)!
        try pidData.write(to: URL(fileURLWithPath: lockPath))

        logger.info(component: "ProcessLockManager", event: "Lock acquired", data: [
            "pid": String(currentPid),
            "lock_path": lockPath
        ])

        return true
    }

    public func releaseLock() throws {
        guard FileManager.default.fileExists(atPath: lockPath) else {
            return
        }

        // Verify this process owns the lock
        let existingPid = getExistingPid()
        if let pid = existingPid, pid == ProcessInfo.processInfo.processIdentifier {
            try FileManager.default.removeItem(atPath: lockPath)
            logger.info(component: "ProcessLockManager", event: "Lock released", data: [
                "pid": String(pid),
                "lock_path": lockPath
            ])
        } else {
            logger.warn(component: "ProcessLockManager", event: "Lock file owned by different process", data: [
                "current_pid": String(ProcessInfo.processInfo.processIdentifier),
                "lock_pid": existingPid.map { String($0) } ?? "nil"
            ])
        }
    }

    public func isLocked() -> Bool {
        guard FileManager.default.fileExists(atPath: lockPath) else {
            return false
        }

        if let pid = getExistingPid() {
            return isProcessRunning(pid)
        }

        return false
    }

    public func getLockPid() -> Int32? {
        return getExistingPid()
    }

    private func getExistingPid() -> Int32? {
        guard FileManager.default.fileExists(atPath: lockPath),
              let pidData = try? Data(contentsOf: URL(fileURLWithPath: lockPath)),
              let pidString = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString) else {
            return nil
        }
        return pid
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        #if os(macOS) || os(Linux)
        // On Unix systems, kill with signal 0 checks if process exists
        return kill(pid, 0) == 0 || errno == EPERM
        #else
        // Fallback: try to read process info
        return true
        #endif
    }
}
