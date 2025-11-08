import Foundation

public struct FocusPath: Equatable, Sendable {
    public let chain: [NodeID]

    public init(chain: [NodeID]) {
        self.chain = chain
    }

    public var isEmpty: Bool {
        chain.isEmpty
    }

    public var current: NodeID? {
        chain.last
    }
}

public actor TUIFocusManager {
    private var focused: FocusPath = FocusPath(chain: [])

    public init() {}

    public func getFocused() -> FocusPath {
        return focused
    }

    public func request(by nodeID: NodeID) {
        focused = FocusPath(chain: [nodeID])
    }

    public func moveNext(scope: NodeID, in tree: TUIRenderable) -> Bool {
        // Simple implementation: find next focusable node in tree
        // In a full implementation, this would traverse the tree
        // and find the next focusable node after the current one
        return false
    }

    public func movePrevious(scope: NodeID, in tree: TUIRenderable) -> Bool {
        // Simple implementation: find previous focusable node
        return false
    }

    public func clear() {
        focused = FocusPath(chain: [])
    }
}
