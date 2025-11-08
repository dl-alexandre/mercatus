import Foundation
@testable import SmartVestor

final class NullTelemetry: TUITelemetryCollector {
    func recordFrame(_ telemetry: FrameTelemetry) async {}
    func incrementCounter(_ key: CounterKey) async {}
    func getCounters() async -> CounterTelemetry {
        return CounterTelemetry()
    }
    func resetCounters() async {}
}

struct TestClock {
    private var current: ContinuousClock.Instant

    init(startingAt instant: ContinuousClock.Instant = .now) {
        self.current = instant
    }

    mutating func advance(by duration: Duration) {
        current = current.advanced(by: duration)
    }

    func now() -> ContinuousClock.Instant {
        return current
    }
}
