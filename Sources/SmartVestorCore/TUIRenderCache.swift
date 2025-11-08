import Foundation

public final actor RenderCache {
    private struct CacheEntry {
        let hash: UInt64
        let surface: Surface
        let bounds: Rect
        let lastVisibleRect: Rect?
        let env: TerminalEnv
    }

    private var cache: [NodeID: CacheEntry] = [:]
    private let maxCells: Int
    private var currentCells: Int = 0

    public init(maxCells: Int = 100000) {
        self.maxCells = maxCells
    }

    public func lookup(_ id: NodeID, _ hash: UInt64, _ env: TerminalEnv) -> Surface? {
        guard let entry = cache[id],
              entry.hash == hash,
              entry.env == env else {
            return nil
        }
        return entry.surface
    }

    public func store(_ id: NodeID, _ hash: UInt64, _ surface: Surface, _ bounds: Rect, _ lastVisibleRect: Rect?, _ env: TerminalEnv) {
        let cells = bounds.size.width * bounds.size.height

        if let existing = cache[id] {
            let oldCells = existing.bounds.size.width * existing.bounds.size.height
            currentCells -= oldCells
        }

        while currentCells + cells > maxCells && !cache.isEmpty {
            if let firstKey = cache.keys.first {
                if let entry = cache.removeValue(forKey: firstKey) {
                    let entryCells = entry.bounds.size.width * entry.bounds.size.height
                    currentCells -= entryCells
                }
            }
        }

        cache[id] = CacheEntry(
            hash: hash,
            surface: surface,
            bounds: bounds,
            lastVisibleRect: lastVisibleRect,
            env: env
        )
        currentCells += cells
    }

    public func invalidateSubtree(root: NodeID) {
        let keysToRemove = cache.keys.filter { $0.isDescendant(of: root) || $0 == root }
        for key in keysToRemove {
            if let entry = cache.removeValue(forKey: key) {
                let cells = entry.bounds.size.width * entry.bounds.size.height
                currentCells -= cells
            }
        }
    }

    public func invalidateByEnv(_ env: TerminalEnv) {
        let keysToRemove = cache.keys.filter { cache[$0]?.env != env }
        for key in keysToRemove {
            if let entry = cache.removeValue(forKey: key) {
                let cells = entry.bounds.size.width * entry.bounds.size.height
                currentCells -= cells
            }
        }
    }

    public func clear() {
        cache.removeAll()
        currentCells = 0
    }
}
