import Foundation

#if os(macOS) || os(Linux)
import Darwin
#endif

actor FrameCoalescer {
    private var latestFrame: String?
    private var isRunning = false
    private let intervalNs: UInt64 = 16_000_000
    private var continuation: CheckedContinuation<Void, Never>?

    func enqueue(_ frame: String) async {
        latestFrame = frame
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
        guard !isRunning else { return }
        isRunning = true
        Task { await self.runLoop() }
    }

    func flush() async {
        if let f = latestFrame {
            latestFrame = nil
            await Runtime.renderBus.write(f)
        }
    }

    func schedule(_ work: @escaping @Sendable () async -> Void) {
        guard !isRunning else { return }
        isRunning = true
        Task {
            try? await Task.sleep(nanoseconds: 16_000_000)
            isRunning = false
            await work()
        }
    }

    private func runLoop() async {
        defer { isRunning = false }
        while !Task.isCancelled {
            guard !Task.isCancelled else { break }
            if let frame = latestFrame {
                latestFrame = nil
                await Runtime.renderBus.write(frame)
                try? await Task.sleep(nanoseconds: intervalNs)
            } else {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    continuation = cont
                }
            }
        }
    }
}
