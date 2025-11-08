import Foundation
import Testing
@testable import SmartVestor

public final class FixedSeedRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64 = 42) {
        self.state = seed
    }

    public func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

public struct FixedClock {
    private var baseTime: Date
    private var increment: TimeInterval

    public init(baseTime: Date = Date(timeIntervalSince1970: 0), increment: TimeInterval = 1.0) {
        self.baseTime = baseTime
        self.increment = increment
    }

    public mutating func now() -> Date {
        let result = baseTime
        baseTime = baseTime.addingTimeInterval(increment)
        return result
    }
}

public struct DeterministicUUIDGenerator {
    private var counter: UInt64

    public init(startingCounter: UInt64 = 0) {
        self.counter = startingCounter
    }

    public mutating func generate() -> UUID {
        let bytes = withUnsafeBytes(of: counter.bigEndian) { Array($0) }
        var uuidBytes: [UInt8] = Array(repeating: 0, count: 16)
        let prefixCount = min(8, bytes.count)
        for i in 0..<prefixCount {
            uuidBytes[i] = bytes[i]
        }
        uuidBytes[8] = 0x40
        uuidBytes[9] = 0x80
        counter += 1
        let uuidTuple: uuid_t = (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )
        return UUID(uuid: uuidTuple)
    }
}

public struct TUITestContext {
    public let terminal: MockTerminalOperations
    public let output: CapturingStream
    public let clock: FixedClock
    public var rng: FixedSeedRNG

    public init(
        terminalSize: TerminalSize = .init(cols: 80, rows: 24),
        clock: FixedClock = FixedClock(),
        rngSeed: UInt64 = 42
    ) {
        self.terminal = MockTerminalOperations(size: terminalSize)
        self.output = CapturingStream()
        self.clock = clock
        self.rng = FixedSeedRNG(seed: rngSeed)
    }

    public func loadSnapshot(name: String) throws -> String {
        let snapshotPath = "Tests/__Snapshots__/tui/\(name).txt"
        guard let data = FileManager.default.contents(atPath: snapshotPath) else {
            throw SnapshotError.missing(name)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw SnapshotError.invalidEncoding(name)
        }
        return content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public func saveSnapshot(name: String, content: String, seed: UInt64 = 42) throws {
        let snapshotDir = "Tests/__Snapshots__/tui"
        if !FileManager.default.fileExists(atPath: snapshotDir) {
            try FileManager.default.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)
        }

        let header = "# size: \(terminal.size.cols)x\(terminal.size.rows)\n# seed: \(seed)\n"
        let normalized = header + content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let snapshotPath = "\(snapshotDir)/\(name).txt"
        try normalized.write(toFile: snapshotPath, atomically: true, encoding: String.Encoding.utf8)
    }

    public func compareSnapshot(actual: String, expected: String) -> (matches: Bool, diff: String) {
        let actualNormalized = ANSINormalizer.strip(actual).replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let expectedNormalized = expected.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if actualNormalized == expectedNormalized {
            return (true, "")
        }

        let actualLines = actualNormalized.components(separatedBy: "\n")
        let expectedLines = expectedNormalized.components(separatedBy: "\n")
        var diff = "Snapshot mismatch:\n"
        let maxLines = max(actualLines.count, expectedLines.count)

        for i in 0..<maxLines {
            let actualLine = i < actualLines.count ? actualLines[i] : "<missing>"
            let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"

            if actualLine != expectedLine {
                diff += "Line \(i + 1):\n"
                diff += "  Expected: \(expectedLine)\n"
                diff += "  Actual:   \(actualLine)\n"
            }
        }

        return (false, diff)
    }
}

public enum SnapshotError: Error {
    case missing(String)
    case invalidEncoding(String)
}

extension TUITestContext {
    public func simulateTerminalResize(to newSize: TerminalSize) {
        terminal.size = newSize
    }
}
