import Foundation

@resultBuilder
public enum TUIViewBuilder {
    public static func buildBlock() -> [TUIRenderable] {
        []
    }

    public static func buildBlock(_ component: TUIRenderable) -> TUIRenderable {
        component
    }

    public static func buildBlock(_ components: TUIRenderable...) -> [TUIRenderable] {
        Array(components)
    }

    public static func buildBlock(_ arrays: [TUIRenderable]...) -> [TUIRenderable] {
        arrays.flatMap { $0 }
    }

    public static func buildOptional(_ component: TUIRenderable?) -> [TUIRenderable] {
        if let component {
            return [component]
        }
        return []
    }

    public static func buildEither(first component: TUIRenderable) -> [TUIRenderable] {
        [component]
    }

    public static func buildEither(second component: TUIRenderable) -> [TUIRenderable] {
        [component]
    }

    public static func buildArray(_ components: [TUIRenderable]) -> [TUIRenderable] {
        components
    }

    public static func buildExpression(_ expression: String) -> TUIRenderable {
        Text(expression)
    }

    public static func buildExpression(_ expression: TUIRenderable) -> TUIRenderable {
        expression
    }

    public static func buildBlock<Content: TUIRenderable>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<C0: TUIRenderable, C1: TUIRenderable>(
        _ c0: C0, _ c1: C1
    ) -> [TUIRenderable] {
        [c0, c1]
    }

    public static func buildBlock<C0: TUIRenderable, C1: TUIRenderable, C2: TUIRenderable>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> [TUIRenderable] {
        [c0, c1, c2]
    }

    public static func buildBlock<C0: TUIRenderable, C1: TUIRenderable, C2: TUIRenderable, C3: TUIRenderable>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> [TUIRenderable] {
        [c0, c1, c2, c3]
    }

    public static func buildBlock<C0: TUIRenderable, C1: TUIRenderable, C2: TUIRenderable, C3: TUIRenderable, C4: TUIRenderable>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> [TUIRenderable] {
        [c0, c1, c2, c3, c4]
    }

    public static func buildBlock<C0: TUIRenderable, C1: TUIRenderable, C2: TUIRenderable, C3: TUIRenderable, C4: TUIRenderable, C5: TUIRenderable>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> [TUIRenderable] {
        [c0, c1, c2, c3, c4, c5]
    }

    public static func buildIf(_ component: TUIRenderable?) -> [TUIRenderable] {
        if let component {
            return [component]
        }
        return []
    }
}
