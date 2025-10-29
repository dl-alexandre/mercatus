import Foundation
import Testing
@testable import Utils

@Suite("Logger Schema Validation Tests", .serialized)
struct LoggerSchemaTests {

    struct CapturedLog: Decodable {
        let schemaVersion: String
        let id: String
        let correlationId: String?
        let timestamp: String
        let level: String
        let component: String
        let event: String
        let data: [String: String]?
    }

    final class LogCapture: @unchecked Sendable {
        private let pipe = Pipe()
        private let originalStdout: FileHandle
        private var logs: [String] = []

        init() {
            originalStdout = FileHandle.standardOutput
        }

        func start() {
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        }

        func stop() -> [String] {
            dup2(originalStdout.fileDescriptor, STDOUT_FILENO)

            let data = pipe.fileHandleForReading.availableData
            if let output = String(data: data, encoding: .utf8) {
                return output.split(separator: "\n").map(String.init)
            }
            return []
        }
    }

    @Test("Logger outputs valid JSON schema")
    func validJsonSchema() throws {
        let fixedDate = Date(timeIntervalSince1970: 1672531200)
        let logger = StructuredLogger(maxLogsPerMinute: 10000, clock: { fixedDate })

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "TestComponent", event: "test_event", data: ["key": "value"])

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let testEventLine = try #require(lines.first(where: { $0.contains("\"event\":\"test_event\"") }))
        let logData = Data(testEventLine.utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.schemaVersion == "1.0")
        #expect(!decoded.id.isEmpty)
        #expect(decoded.level == "INFO")
        #expect(decoded.component == "TestComponent")
        #expect(decoded.event == "test_event")
        #expect(decoded.data?["key"] == "value")
    }

    @Test("Logger includes schema version 1.0")
    func schemaVersion() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.schemaVersion == "1.0")
    }

    @Test("Logger generates unique IDs")
    func uniqueIds() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event1")
        logger.info(component: "Test", event: "event2")
        logger.info(component: "Test", event: "event3")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 3)

        var ids = Set<String>()
        for line in lines.prefix(3) {
            let logData = Data(line.utf8)
            let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)
            ids.insert(decoded.id)
        }

        #expect(ids.count == 3)
    }

    @Test("Logger formats timestamps in ISO8601 with fractional seconds")
    func timestampFormat() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.timestamp.contains("T"))
        #expect(decoded.timestamp.contains("."))
        #expect(decoded.timestamp.contains("Z"))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: decoded.timestamp)
        #expect(parsed != nil)
    }

    @Test("Logger outputs all log levels correctly")
    func allLogLevels() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.debug(component: "Test", event: "debug_event")
        logger.info(component: "Test", event: "info_event")
        logger.warn(component: "Test", event: "warn_event")
        logger.error(component: "Test", event: "error_event")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 4)

        let levels = try lines.prefix(4).map { line -> String in
            let logData = Data(line.utf8)
            let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)
            return decoded.level
        }

        #expect(levels.contains("DEBUG"))
        #expect(levels.contains("INFO"))
        #expect(levels.contains("WARN"))
        #expect(levels.contains("ERROR"))
    }

    @Test("Logger includes correlation ID when provided")
    func correlationId() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event", correlationId: "corr-123")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.correlationId == "corr-123")
    }

    @Test("Logger omits data field when empty")
    func emptyDataOmitted() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.data == nil)
    }

    @Test("Logger includes data field when provided")
    func dataFieldIncluded() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event", data: [
            "key1": "value1",
            "key2": "value2"
        ])

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.data != nil)
        #expect(decoded.data?["key1"] == "value1")
        #expect(decoded.data?["key2"] == "value2")
    }

    @Test("Logger outputs compact JSON without formatting")
    func compactJson() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event", data: ["key": "value"])

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let line = lines[0]
        #expect(!line.contains("  "))
        #expect(!line.contains("\n"))
    }

    @Test("Logger handles special characters in data")
    func specialCharactersInData() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event", data: [
            "message": "Hello \"world\" with \\ backslash",
            "unicode": "🚀 emoji test"
        ])

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.data?["message"] == "Hello \"world\" with \\ backslash")
        #expect(decoded.data?["unicode"] == "🚀 emoji test")
    }

    @Test("Logger appends newline to each log entry")
    func newlineAppended() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        logger.info(component: "Test", event: "event")

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        try? pipe.fileHandleForWriting.close()

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let testEventLine = try #require(lines.first(where: { $0.contains("\"event\":\"event\"") }))
        #expect(testEventLine.hasSuffix("\n") == false)  // the line itself doesn't end with \n since split removes it
        #expect(output.contains(testEventLine + "\n"))
    }

    @Test("Logger enforces rate limiting")
    func rateLimiting() throws {
        let logger = StructuredLogger(maxLogsPerMinute: 5)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        for i in 1...10 {
            logger.info(component: "Test", event: "event_\(i)")
        }

        Thread.sleep(forTimeInterval: 0.2)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        let nonWarningLines = lines.filter { !$0.contains("\"event\":\"logs_dropped_rate_limit\"") }
        #expect(nonWarningLines.count <= 5)
    }

    @Test("Logger supports Encodable data types")
    func encodableDataSupport() throws {
        struct TestData: Encodable {
            let userId: Int
            let username: String
            let isActive: Bool
        }

        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        let testData = TestData(userId: 42, username: "alice", isActive: true)
        logger.info(component: "Test", event: "user_event", data: testData)

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.data?["userId"] == "42")
        #expect(decoded.data?["username"] == "alice")
        #expect(decoded.data?["isActive"] == "true")
    }

    @Test("Logger handles nested Encodable structures")
    func nestedEncodableSupport() throws {
        struct Address: Encodable {
            let street: String
            let city: String
        }

        struct User: Encodable {
            let name: String
            let addresses: [Address]
        }

        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        let user = User(
            name: "Bob",
            addresses: [
                Address(street: "Main St", city: "NYC"),
                Address(street: "Oak Ave", city: "SF")
            ]
        )
        logger.info(component: "Test", event: "user_data", data: user)

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 1)

        let logData = Data(lines[0].utf8)
        let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

        #expect(decoded.data?["name"] == "Bob")
        #expect(decoded.data?["addresses"]?.contains("Main St") == true)
    }

    @Test("Logger handles Encodable with all log levels")
    func encodableAllLevels() throws {
        struct EventData: Encodable {
            let action: String
            let count: Int
        }

        let logger = StructuredLogger(maxLogsPerMinute: 10000)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        let eventData = EventData(action: "click", count: 5)
        logger.debug(component: "Test", event: "debug_event", data: eventData)
        logger.info(component: "Test", event: "info_event", data: eventData)
        logger.warn(component: "Test", event: "warn_event", data: eventData)
        logger.error(component: "Test", event: "error_event", data: eventData)

        Thread.sleep(forTimeInterval: 0.1)

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        #expect(lines.count >= 4)

        for line in lines.prefix(4) {
            let logData = Data(line.utf8)
            let decoded = try JSONDecoder().decode(CapturedLog.self, from: logData)

            #expect(decoded.data?["action"] == "click")
            #expect(decoded.data?["count"] == "5")
        }
    }
}
