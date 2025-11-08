import Foundation

public protocol PriceAwarePanelRenderer: PanelRenderer {
    func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool,
        prices: [String: Double]
    ) async -> RenderedPanel
}

public extension PriceAwarePanelRenderer {
    func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool,
        prices: [String: Double]
    ) async -> RenderedPanel {
        return await render(
            input: input,
            layout: layout,
            colorManager: colorManager,
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported,
            isFocused: isFocused
        )
    }
}
