import Foundation
import Utils

public class FileLogger: @unchecked Sendable {
    private let logPath: String
    private var fileHandle: FileHandle?
    private let queue: DispatchQueue
    private let logger: StructuredLogger
    private let maxFileSize: Int64
    private let maxFiles: Int

    public init(
        logPath: String = "smartvestor-automation.log",
        maxFileSize: Int64 = 10 * 1024 * 1024, // 10MB
        maxFiles: Int = 5,
        logger: StructuredLogger = StructuredLogger()
    ) throws {
        self.logPath = logPath
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
        self.logger = logger
        self.queue = DispatchQueue(label: "com.smartvestor.filelogger", qos: .utility)

        // Create log file if it doesn't exist
        let fileURL = URL(fileURLWithPath: logPath)
        let directory = fileURL.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        // Open file handle for appending
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        self.fileHandle?.seekToEndOfFile()
    }

    deinit {
        fileHandle?.closeFile()
    }

    public func log(level: StructuredLogger.Level, component: String, event: String, data: [String: String] = [:]) {
        queue.async { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let levelStr = level.rawValue
            let dataJSON = try? JSONSerialization.data(withJSONObject: data)
            let dataStr = dataJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

            let logLine = "\(timestamp) | \(levelStr) | \(component) | \(event) | \(dataStr)\n"

            if let logData = logLine.data(using: .utf8) {
                handle.write(logData)
                handle.synchronizeFile()

                // Check if rotation is needed
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: self.logPath)[.size] as? Int64,
                   fileSize > self.maxFileSize {
                    try? self.rotate()
                }
            }
        }
    }

    private func rotate() throws {
        guard let handle = fileHandle else { return }
        handle.closeFile()
        fileHandle = nil

        // Rotate existing logs: .log -> .log.1, .log.1 -> .log.2, etc.
        for i in (1..<maxFiles).reversed() {
            let oldPath = i == 1 ? logPath : "\(logPath).\(i - 1)"
            let newPath = "\(logPath).\(i)"

            if FileManager.default.fileExists(atPath: oldPath) {
                if FileManager.default.fileExists(atPath: newPath) {
                    try FileManager.default.removeItem(atPath: newPath)
                }
                try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            }
        }

        // Move current log to .log.1
        let rotatedPath = "\(logPath).1"
        if FileManager.default.fileExists(atPath: logPath) {
            if FileManager.default.fileExists(atPath: rotatedPath) {
                try FileManager.default.removeItem(atPath: rotatedPath)
            }
            try FileManager.default.moveItem(atPath: logPath, toPath: rotatedPath)
        }

        // Create new log file
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        fileHandle?.seekToEndOfFile()

        logger.info(component: "FileLogger", event: "Log file rotated", data: [
            "log_path": logPath
        ])

        // Remove old log files beyond maxFiles
        for i in maxFiles... {
            let oldLogPath = "\(logPath).\(i)"
            if FileManager.default.fileExists(atPath: oldLogPath) {
                try? FileManager.default.removeItem(atPath: oldLogPath)
            } else {
                break
            }
        }
    }

    public func close() {
        queue.sync {
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }
}

// Wrapper that logs to both console (via StructuredLogger) and file
public class DualLogger: @unchecked Sendable {
    private let consoleLogger: StructuredLogger
    private let fileLogger: FileLogger?

    public init(
        consoleLogger: StructuredLogger = StructuredLogger(),
        fileLogger: FileLogger? = nil
    ) {
        self.consoleLogger = consoleLogger
        self.fileLogger = fileLogger
    }

    public func log(
        level: StructuredLogger.Level,
        component: String,
        event: String,
        data: [String: String] = [:]
    ) {
        // Log to console
        consoleLogger.log(level: level, component: component, event: event, data: data)

        // Log to file
        fileLogger?.log(level: level, component: component, event: event, data: data)
    }

    public func info(component: String, event: String, data: [String: String] = [:]) {
        log(level: .info, component: component, event: event, data: data)
    }

    public func warn(component: String, event: String, data: [String: String] = [:]) {
        log(level: .warn, component: component, event: event, data: data)
    }

    public func error(component: String, event: String, data: [String: String] = [:]) {
        log(level: .error, component: component, event: event, data: data)
    }

    public func debug(component: String, event: String, data: [String: String] = [:]) {
        log(level: .debug, component: component, event: event, data: data)
    }

    public func close() {
        fileLogger?.close()
    }
}
