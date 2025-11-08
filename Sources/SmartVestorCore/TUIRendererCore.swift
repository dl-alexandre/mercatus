import Foundation
import Core

public enum TUIRendererCore {
    public static func render(_ component: TUIRenderable, into buf: inout TerminalBuffer, at origin: Point = .zero) {
        let viewport = Viewport(rect: Rect(origin: .zero, size: buf.size))
        render(component, into: &buf, at: origin, viewport: viewport)
    }

    public static func render(_ component: TUIRenderable, into buf: inout TerminalBuffer, at origin: Point, viewport: Viewport) {
        let measured = component.measure(in: buf.size)
        let bounds = Rect(origin: origin, size: measured)

        // Viewport culling: skip if completely outside viewport
        guard let clip = viewport.intersection(bounds) else {
            return
        }

        component.render(into: &buf, at: origin)

        var currentY = origin.y
        for child in component.children() {
            let childSize = child.measure(in: Size(width: buf.size.width - origin.x, height: buf.size.height - currentY))
            let childOrigin = Point(x: origin.x, y: currentY)
            let childBounds = Rect(origin: childOrigin, size: childSize)

            // Only render children that intersect viewport
            if viewport.intersection(childBounds) != nil {
                render(child, into: &buf, at: childOrigin, viewport: viewport)
            }
            currentY += childSize.height
        }
    }

    public static func renderDirty(_ component: TUIRenderable, dirtyNodes: Set<NodeID>, into buf: inout TerminalBuffer, at origin: Point = .zero) {
        let viewport = Viewport(rect: Rect(origin: .zero, size: buf.size))
        renderDirty(component, dirtyNodes: dirtyNodes, into: &buf, at: origin, viewport: viewport)
    }

    public static func renderDirty(_ component: TUIRenderable, dirtyNodes: Set<NodeID>, into buf: inout TerminalBuffer, at origin: Point, viewport: Viewport) {
        guard dirtyNodes.contains(component.nodeID) || !component.dirtyReasons.isEmpty else {
            return
        }

        let measured = component.measure(in: buf.size)
        let bounds = Rect(origin: origin, size: measured)

        // Viewport culling
        guard viewport.intersection(bounds) != nil else {
            return
        }

        component.render(into: &buf, at: origin)

        var currentY = origin.y
        for child in component.children() {
            let childSize = child.measure(in: Size(width: buf.size.width - origin.x, height: buf.size.height - currentY))
            let childOrigin = Point(x: origin.x, y: currentY)
            let childBounds = Rect(origin: childOrigin, size: childSize)

            if viewport.intersection(childBounds) != nil {
                renderDirty(child, dirtyNodes: dirtyNodes, into: &buf, at: childOrigin, viewport: viewport)
            }
            currentY += childSize.height
        }
    }

    public static func measure(_ component: TUIRenderable, in size: Size) -> Size {
        return component.measure(in: size)
    }
}
