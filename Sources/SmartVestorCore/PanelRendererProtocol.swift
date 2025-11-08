import Foundation

public struct RenderedPanel: Sendable {
    public let lines: [String]
    public let width: Int
    public let height: Int
    public let hasBorder: Bool

    public init(lines: [String], width: Int, height: Int, hasBorder: Bool = true) {
        self.lines = lines
        self.width = width
        self.height = height
        self.hasBorder = hasBorder
    }

    public func render() -> String {
        return lines.joined(separator: "\n")
    }
}

public protocol PanelRendererProtocol: Sendable {
    associatedtype Input

    var panelType: PanelType { get }
    var identifier: String { get }

    func render(
        input: Input,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool
    ) async -> RenderedPanel
}

public protocol PanelRenderer: PanelRendererProtocol where Input == TUIUpdate {
}

public extension PanelRenderer {
    func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool = false
    ) async -> RenderedPanel {
        return await render(
            input: input,
            layout: layout,
            colorManager: colorManager,
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )
    }
}
