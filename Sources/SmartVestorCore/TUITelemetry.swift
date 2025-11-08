import Foundation
import Core

public struct FrameTelemetry: Sendable {
    public var nodesVisited: Int = 0
    public var linesChanged: Int = 0
    public var bytesWritten: Int = 0
    public var timeInBridgeMs: Double = 0
    public var timeInLayoutMs: Double = 0
    public var timeInDiffMs: Double = 0
    public var timeInWriteMs: Double = 0

    public init() {}
}

public struct CounterTelemetry: Sendable {
    public var coalescedUpdates: Int = 0
    public var droppedLowPriorityUpdates: Int = 0
    public var resizeEvents: Int = 0
    public var renderFrames: Int = 0

    public init() {}
}

public protocol TUITelemetryCollector: Sendable {
    func recordFrame(_ telemetry: FrameTelemetry) async
    func incrementCounter(_ key: CounterKey) async
    func getCounters() async -> CounterTelemetry
    func resetCounters() async
}

public enum CounterKey: String, Sendable {
    case coalescedUpdates
    case droppedLowPriorityUpdates
    case resizeEvents
    case renderFrames
}

public actor DefaultTUITelemetryCollector: TUITelemetryCollector {
    private var counters = CounterTelemetry()

    public init() {}

    public func recordFrame(_ telemetry: FrameTelemetry) async {
    }

    public func incrementCounter(_ key: CounterKey) async {
        switch key {
        case .coalescedUpdates:
            counters.coalescedUpdates += 1
        case .droppedLowPriorityUpdates:
            counters.droppedLowPriorityUpdates += 1
        case .resizeEvents:
            counters.resizeEvents += 1
        case .renderFrames:
            counters.renderFrames += 1
        }
    }

    public func getCounters() async -> CounterTelemetry {
        return counters
    }

    public func resetCounters() async {
        counters = CounterTelemetry()
    }
}
