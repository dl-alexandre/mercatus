import Foundation
#if os(macOS) || os(Linux)
import Darwin
#endif

public final class TerminalOutputQueue: @unchecked Sendable {
    private let queue: DispatchQueue
    private let semaphore: DispatchSemaphore

    public static let shared = TerminalOutputQueue()

    public init(label: String = "com.smartvestor.terminal.output", qos: DispatchQoS = .userInteractive) {
        self.queue = DispatchQueue(label: label, qos: qos)
        self.semaphore = DispatchSemaphore(value: 1)
    }

    public func write(_ data: Data) {
        queue.sync {
            self.writeDataWithRetry(data)
        }
    }

    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }

    public func flush() {
        queue.sync {
            fflush(stdout)
            fflush(stderr)
        }
    }

    public func synchronizedFlush() {
        semaphore.wait()
        defer { semaphore.signal() }
        flush()
    }

    private func writeDataWithRetry(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        Task {
            await Runtime.renderBus.write(string)
        }
    }
}
