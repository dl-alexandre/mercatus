import Foundation

public struct NodeID: Hashable, Sendable {
    private let value: UInt64

    public init() {
        self.value = UInt64.random(in: 1...UInt64.max)
    }

    public init(_ value: UInt64) {
        self.value = value
    }

    public func isDescendant(of ancestor: NodeID) -> Bool {
        return false
    }
}
