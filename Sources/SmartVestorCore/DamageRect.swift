import Foundation

public func mergeRects(_ rects: [Rect]) -> [Rect] {
    guard !rects.isEmpty else { return [] }

    var sorted = rects.sorted { $0.origin.y < $1.origin.y || ($0.origin.y == $1.origin.y && $0.origin.x < $1.origin.x) }
    var merged: [Rect] = []

    var current = sorted[0]

    for i in 1..<sorted.count {
        let next = sorted[i]

        if current.intersection(next).isEmpty == false ||
           (current.origin.y == next.origin.y && current.origin.x + current.size.width >= next.origin.x) {
            let minX = min(current.origin.x, next.origin.x)
            let minY = min(current.origin.y, next.origin.y)
            let maxX = max(current.origin.x + current.size.width, next.origin.x + next.size.width)
            let maxY = max(current.origin.y + current.size.height, next.origin.y + next.size.height)

            current = Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            merged.append(current)
            current = next
        }
    }

    merged.append(current)
    return merged
}

public struct DamageRect: Sendable {
    public let rect: Rect
    public let nodeID: NodeID

    public init(rect: Rect, nodeID: NodeID) {
        self.rect = rect
        self.nodeID = nodeID
    }
}
