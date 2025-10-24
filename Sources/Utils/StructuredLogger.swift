import Foundation

/// Structured logger that emits JSON encoded log entries to stdout asynchronously.
public final class StructuredLogger {
    public enum Level: String, Sendable, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

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
    private let clock: @Sendable () -> Date
    private var logTimestamps: [TimeInterval] = []
    private let maxLogsPerMinute: Int
    private let rateInterval: TimeInterval = 60
    private var droppedLogCount: Int = 0
    private var lastDropWarningTime: TimeInterval = 0
    private let dropWarningInterval: TimeInterval = 60

    public init(maxLogsPerMinute: Int = 1000, clock: @escaping @Sendable () -> Date = Date.init) {
        self.maxLogsPerMinute = max(1, maxLogsPerMinute)
        self.clock = clock

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        self.encoder = encoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter

        self.queue = DispatchQueue(label: "com.mercatus.logger", qos: .utility)

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
        let cutoff = date.timeIntervalSince1970 - rateInterval
        logTimestamps.removeAll { $0 < cutoff }
        guard logTimestamps.count < maxLogsPerMinute else { return false }
        logTimestamps.append(date.timeIntervalSince1970)
        return true
    }

    private func recordDroppedLog(at date: Date) {
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
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = write(STDOUT_FILENO, baseAddress, buffer.count)
        }
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
}

extension StructuredLogger: @unchecked Sendable {}
