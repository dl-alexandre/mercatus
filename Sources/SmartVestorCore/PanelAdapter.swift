import Foundation
import Core

public final class PanelAdapter: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let renderedLines: [String]
    private let layout: PanelLayout
    private let cachedMeasuredSize: Size
    public var canReceiveFocus: Bool { false }

    public init(
        panelType: PanelType,
        renderedLines: [String],
        layout: PanelLayout
    ) {
        self.id = panelType.rawValue
        self.nodeID = NodeID()
        self.renderedLines = renderedLines
        self.layout = layout
        self.cachedMeasuredSize = Size(width: layout.width, height: layout.height)
    }

    public func measure(in size: Size) -> Size {
        return cachedMeasuredSize
    }

    public var panelType: PanelType {
        if let stringID = id.base as? String, let type = PanelType(rawValue: stringID) {
            return type
        }
        return .custom
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        for (lineIdx, line) in renderedLines.enumerated() {
            let y = origin.y + lineIdx
            if y < buf.size.height {
                buf.write(line, at: Point(x: origin.x, y: y))
            }
        }
    }

    public func children() -> [TUIRenderable] {
        return []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(id)
        hasher.combine(layout.width)
        hasher.combine(layout.height)
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }
}
