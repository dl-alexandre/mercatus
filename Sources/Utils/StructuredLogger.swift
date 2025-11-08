import Foundation

/// Structured logger that emits JSON encoded log entries to stdout asynchronously.
public final class StructuredLogger {
    public enum Level: String, Sendable, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private let enabled: Bool
    private let logFilePath: String?
    private let alsoPrintToStderr: Bool
    private var fileHandle: FileHandle?
    private var fileWriteFailed = false

    private struct LogEnvelope: Encodable {
        let schemaVersion: String
        let id: String
        let correlationId: String?
        let timestamp: String
        let level: String
        let component: String
        let event: String
        let data: [String: String]?
    }

    private let encoder: JSONEncoder
    private let timestampFormatter: ISO8601DateFormatter
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<String>()
    private let clock: @Sendable () -> Date
    private var logTimestamps: [TimeInterval] = []
    private let maxLogsPerMinute: Int
    private let rateInterval: TimeInterval = 60
    private var droppedLogCount: Int = 0
    private var lastDropWarningTime: TimeInterval = 0
    private let lock = NSLock()
    private let dropWarningInterval: TimeInterval = 60

    public init(
        maxLogsPerMinute: Int = 1000,
        clock: @escaping @Sendable () -> Date = Date.init,
        enabled: Bool = true,
        logFilePath: String? = nil,
        alsoPrintToStderr: Bool = false
    ) {
        self.maxLogsPerMinute = max(1, maxLogsPerMinute)
        self.clock = clock
        self.enabled = enabled
        self.alsoPrintToStderr = alsoPrintToStderr

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        self.encoder = encoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter

        self.queue = DispatchQueue(label: "com.mercatus.logger", qos: .utility)
        queue.setSpecific(key: queueKey, value: "com.mercatus.logger")

        let resolvedPath = StructuredLogger.resolveLogFilePath(preferredPath: logFilePath)
        self.logFilePath = resolvedPath

        signal(SIGPIPE, SIG_IGN)
    }

    public func log(
        level: Level,
        component: String,
        event: String,
        data: [String: String] = [:],
        id: String = UUID().uuidString,
        correlationId: String? = nil
    ) {
        guard enabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let now = self.clock()
            guard self.consumeToken(for: now) else {
                self.recordDroppedLog(at: now)
                return
            }

            let entry = LogEnvelope(
                schemaVersion: "1.0",
                id: id,
                correlationId: correlationId,
                timestamp: self.timestampFormatter.string(from: now),
                level: level.rawValue,
                component: component,
                event: event,
                data: data.isEmpty ? nil : data
            )

            do {
                var payload = try self.encoder.encode(entry)
                payload.append(0x0A)
                self.writeToStdout(payload)
            } catch {
                self.writeFallbackEncodingError(component: component, event: event, error: error)
            }
        }
    }

    public func debug(component: String, event: String, data: [String: String] = [:], correlationId: String? = nil) {
        log(level: .debug, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func info(component: String, event: String, data: [String: String] = [:], correlationId: String? = nil) {
        log(level: .info, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func warn(component: String, event: String, data: [String: String] = [:], correlationId: String? = nil) {
        log(level: .warn, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func error(component: String, event: String, data: [String: String] = [:], correlationId: String? = nil) {
        log(level: .error, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func log<T: Encodable>(
        level: Level,
        component: String,
        event: String,
        data: T,
        id: String = UUID().uuidString,
        correlationId: String? = nil
    ) {
        guard enabled else { return }
        let stringData = encodeToStringDictionary(data)
        log(level: level, component: component, event: event, data: stringData, id: id, correlationId: correlationId)
    }

    public func debug<T: Encodable>(component: String, event: String, data: T, correlationId: String? = nil) {
        log(level: .debug, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func info<T: Encodable>(component: String, event: String, data: T, correlationId: String? = nil) {
        log(level: .info, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func warn<T: Encodable>(component: String, event: String, data: T, correlationId: String? = nil) {
        log(level: .warn, component: component, event: event, data: data, correlationId: correlationId)
    }

    public func error<T: Encodable>(component: String, event: String, data: T, correlationId: String? = nil) {
        log(level: .error, component: component, event: event, data: data, correlationId: correlationId)
    }

    private func encodeToStringDictionary<T: Encodable>(_ value: T) -> [String: String] {
        do {
            let jsonData = try encoder.encode(value)
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return ["_encoded": String(data: jsonData, encoding: .utf8) ?? "encoding_failed"]
            }

            return jsonObject.reduce(into: [:]) { result, pair in
                result[pair.key] = stringify(pair.value)
            }
        } catch {
            return ["_encoding_error": error.localizedDescription]
        }
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            let items = array.map { stringify($0) }
            return "[\(items.joined(separator: ","))]"
        case let dict as [String: Any]:
            let pairs = dict.map { "\($0.key):\(stringify($0.value))" }
            return "{\(pairs.joined(separator: ","))}"
        default:
            return "\(value)"
        }
    }

    private func consumeToken(for date: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = date.timeIntervalSince1970 - rateInterval
        logTimestamps.removeAll { $0 < cutoff }
        guard logTimestamps.count < maxLogsPerMinute else { return false }
        logTimestamps.append(date.timeIntervalSince1970)
        return true
    }

    private func recordDroppedLog(at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        droppedLogCount += 1
        let now = date.timeIntervalSince1970

        guard now - lastDropWarningTime >= dropWarningInterval else { return }
        lastDropWarningTime = now

        let warning = LogEnvelope(
            schemaVersion: "1.0",
            id: UUID().uuidString,
            correlationId: nil,
            timestamp: timestampFormatter.string(from: date),
            level: Level.warn.rawValue,
            component: "StructuredLogger",
            event: "logs_dropped_rate_limit",
            data: ["count": "\(droppedLogCount)"]
        )

        guard var payload = try? encoder.encode(warning) else { return }
        payload.append(0x0A)
        writeToStdout(payload)

        droppedLogCount = 0
    }

    public func getDroppedLogCount() -> Int {
        var count = 0
        queue.sync {
            count = droppedLogCount
        }
        return count
    }

    private func writeToStdout(_ data: Data) {
        if let path = logFilePath, !fileWriteFailed {
            do {
                try writeToFile(path: path, data: data)
                if alsoPrintToStderr {
                    fallbackWriteToStderr(data)
                }
                return
            } catch {
                fileWriteFailed = true
                fallbackWriteToStderr(data)
                return
            }
        }

        fallbackWriteToStderr(data)
    }

    private func writeFallbackEncodingError(component: String, event: String, error: Swift.Error) {
        let fallback = LogEnvelope(
            schemaVersion: "1.0",
            id: UUID().uuidString,
            correlationId: nil,
            timestamp: timestampFormatter.string(from: clock()),
            level: Level.error.rawValue,
            component: component,
            event: "\(event)_encoding_failure",
            data: ["reason": error.localizedDescription]
        )

        guard var payload = try? encoder.encode(fallback) else { return }
        payload.append(0x0A)
        writeToStdout(payload)
    }

    private func writeToFile(path: String, data: Data) throws {
        let expandedPath = StructuredLogger.expandPath(path)
        if fileHandle == nil {
            fileHandle = try createFileHandle(at: expandedPath)
        }

        guard let handle = fileHandle else {
            throw NSError(domain: "StructuredLogger", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create log file handle"])
        }

        try handle.write(contentsOf: data)
        if #available(macOS 10.15.4, *) {
            try handle.synchronize()
        } else {
            handle.synchronizeFile()
        }
    }

    private func createFileHandle(at path: String) throws -> FileHandle {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        if #available(macOS 10.15, *) {
            try handle.seekToEnd()
        } else {
            handle.seekToEndOfFile()
        }
        return handle
    }

    private func fallbackWriteToStderr(_ data: Data) {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = write(STDERR_FILENO, baseAddress, buffer.count)
            fflush(stderr)
        }
    }

    private static func resolveLogFilePath(preferredPath: String?) -> String? {
        let trimmedPreferred = preferredPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPreferred, !trimmedPreferred.isEmpty {
            return expandPath(trimmedPreferred)
        }

        if let envPath = ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty {
            return expandPath(envPath)
        }

        return nil
    }

    private static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }

    deinit {
        let handle = fileHandle
        fileHandle = nil

        if let handle = handle {
            if DispatchQueue.getSpecific(key: queueKey) != nil {
                if #available(macOS 10.15.4, *) {
                    try? handle.close()
                } else {
                    handle.closeFile()
                }
            } else {
                queue.async {
                    if #available(macOS 10.15.4, *) {
                        try? handle.close()
                    } else {
                        handle.closeFile()
                    }
                }
            }
        }
    }
}

extension StructuredLogger: @unchecked Sendable {}

public func createTestLogger() -> StructuredLogger {
    return StructuredLogger(maxLogsPerMinute: 1000, enabled: false)
}
