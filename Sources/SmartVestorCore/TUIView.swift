import Foundation

public protocol TUIView: TUIRenderable {
    associatedtype Body: TUIRenderable
    @TUIViewBuilder var body: Body { get }
}

extension TUIView {
    public var id: AnyHashable {
        AnyHashable(ObjectIdentifier(Self.self))
    }

    public var nodeID: NodeID {
        NodeID()
    }

    public func render(into buffer: inout TerminalBuffer, at origin: Point) {
        body.render(into: &buffer, at: origin)
    }

    public func measure(in size: Size) -> Size {
        return body.measure(in: size)
    }

    public func children() -> [TUIRenderable] {
        return [body]
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(id)
    }

    public func onFocusChange(_ focused: Bool) {
        // Default: no-op, components can override
    }
}
