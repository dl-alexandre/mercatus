import Foundation

public actor UpdateRateLimiter {
    private var lastUpdateTime: Date?
    private let minInterval: TimeInterval
    private var pendingUpdate: (() async -> Void)?
    private var scheduledTask: Task<Void, Never>?

    public init(minInterval: TimeInterval = 0.1) {
        self.minInterval = minInterval
    }

    public func throttle(_ update: @escaping @Sendable () async -> Void) async {
        let now = Date()

        if let lastTime = lastUpdateTime {
            let timeSinceLastUpdate = now.timeIntervalSince(lastTime)

            if timeSinceLastUpdate < minInterval {
                pendingUpdate = update

                if scheduledTask == nil {
                    let delay = minInterval - timeSinceLastUpdate
                    scheduledTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        await self.processPendingUpdate()
                    }
                }
                return
            }
        }

        lastUpdateTime = now
        await update()
    }

    private func processPendingUpdate() async {
        scheduledTask = nil

        if let update = pendingUpdate {
            pendingUpdate = nil
            let now = Date()
            lastUpdateTime = now
            await update()
        }
    }

    public func reset() async {
        lastUpdateTime = nil
        pendingUpdate = nil
        scheduledTask?.cancel()
        scheduledTask = nil
    }
}
