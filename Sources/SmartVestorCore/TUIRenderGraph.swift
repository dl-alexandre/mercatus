import Foundation

public final class RenderGraph: @unchecked Sendable {
    private var parentMap: [NodeID: NodeID] = [:]
    private var childrenMap: [NodeID: [NodeID]] = [:]
    private var dirtyNodes: Set<NodeID> = []
    private let lock = NSLock()

    public init() {}

    public func addNode(_ nodeID: NodeID, parent: NodeID?) {
        lock.lock()
        defer { lock.unlock() }

        if let parent = parent {
            parentMap[nodeID] = parent
            if childrenMap[parent] == nil {
                childrenMap[parent] = []
            }
            childrenMap[parent]?.append(nodeID)
        }
    }

    public func markDirty(_ nodeID: NodeID) {
        lock.lock()
        defer { lock.unlock() }
        dirtyNodes.insert(nodeID)
    }

    public func markClean(_ nodeID: NodeID) {
        lock.lock()
        defer { lock.unlock() }
        dirtyNodes.remove(nodeID)
    }

    public func isDirty(_ nodeID: NodeID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return dirtyNodes.contains(nodeID)
    }

    public func getDirtySubtree(_ rootID: NodeID) -> Set<NodeID> {
        lock.lock()
        defer { lock.unlock() }

        var result: Set<NodeID> = []
        var queue: [NodeID] = [rootID]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if dirtyNodes.contains(current) {
                result.insert(current)
            }
            if let children = childrenMap[current] {
                queue.append(contentsOf: children)
            }
        }

        return result
    }

    public func invalidateSubtree(_ rootID: NodeID) {
        lock.lock()
        defer { lock.unlock() }

        var queue: [NodeID] = [rootID]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            dirtyNodes.insert(current)
            if let children = childrenMap[current] {
                queue.append(contentsOf: children)
            }
        }
    }

    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        dirtyNodes.removeAll()
    }
}
