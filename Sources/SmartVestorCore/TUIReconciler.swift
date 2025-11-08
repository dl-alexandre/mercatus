import Foundation

public struct RenderIntent: Sendable {
    public let root: TUIRenderable
    public let priority: RenderPriority

    public init(root: TUIRenderable, priority: RenderPriority = .normal) {
        self.root = root
        self.priority = priority
    }
}

public enum RenderPriority: Comparable, Sendable {
    case input
    case normal
    case telemetry

    public static func < (lhs: RenderPriority, rhs: RenderPriority) -> Bool {
        switch (lhs, rhs) {
        case (.input, _): return false
        case (.normal, .input): return true
        case (.normal, .telemetry): return false
        case (.telemetry, .input): return true
        case (.telemetry, .normal): return true
        case (_, _): return false
        }
    }
}

public protocol TUIReconciler: Sendable {
    func submit(intent: RenderIntent) async
}
