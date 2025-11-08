import Foundation

public struct Viewport: Equatable, Sendable {
    public let rect: Rect

    public init(rect: Rect) {
        self.rect = rect
    }

    public func intersection(_ other: Rect) -> Rect? {
        let minX = max(rect.origin.x, other.origin.x)
        let minY = max(rect.origin.y, other.origin.y)
        let maxX = min(rect.origin.x + rect.size.width, other.origin.x + other.size.width)
        let maxY = min(rect.origin.y + rect.size.height, other.origin.y + other.size.height)

        if minX < maxX && minY < maxY {
            return Rect(origin: Point(x: minX, y: minY), size: Size(width: maxX - minX, height: maxY - minY))
        }
        return nil
    }

    public func contains(_ point: Point) -> Bool {
        return point.x >= rect.origin.x && point.x < rect.origin.x + rect.size.width &&
               point.y >= rect.origin.y && point.y < rect.origin.y + rect.size.height
    }

    public func contains(_ other: Rect) -> Bool {
        return other.origin.x >= rect.origin.x &&
               other.origin.y >= rect.origin.y &&
               other.origin.x + other.size.width <= rect.origin.x + rect.size.width &&
               other.origin.y + other.size.height <= rect.origin.y + rect.size.height
    }
}

public protocol LayoutNode: Sendable {
    var frame: Rect { get }
    func draw(into surface: inout TerminalBuffer, clip: Rect)
}

extension TUIRenderable {
    public var frame: Rect {
        // Default implementation - components should override
        return Rect(origin: .zero, size: measure(in: Size(width: Int.max, height: Int.max)))
    }
}
