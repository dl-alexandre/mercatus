import Foundation

public struct PanelEntry: Sendable {
    public let identifier: String
    public let panelType: PanelType
    public let renderer: AnyPanelRenderer
    public let priority: Int

    public init(identifier: String, panelType: PanelType, renderer: AnyPanelRenderer, priority: Int = 0) {
        self.identifier = identifier
        self.panelType = panelType
        self.renderer = renderer
        self.priority = priority
    }
}

public final class AnyPanelRenderer: @unchecked Sendable {
    private let _render: (TUIUpdate, PanelLayout, ColorManagerProtocol, BorderStyle, Bool) async -> RenderedPanel
    private let _identifier: String
    private let _panelType: PanelType

    public init<R: PanelRenderer>(_ renderer: R) {
        self._identifier = renderer.identifier
        self._panelType = renderer.panelType
        self._render = { input, layout, colorManager, borderStyle, unicodeSupported in
            return await renderer.render(
                input: input,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: unicodeSupported
            )
        }
    }

    public var identifier: String {
        return _identifier
    }

    public var panelType: PanelType {
        return _panelType
    }

    public func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool
    ) async -> RenderedPanel {
        return await _render(input, layout, colorManager, borderStyle, unicodeSupported)
    }
}

public final class PanelRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var panels: [String: PanelEntry] = [:]
    private var panelsByType: [PanelType: [String]] = [:]

    public init() {}

    public func register<R: PanelRenderer>(_ renderer: R, priority: Int = 0) {
        lock.lock()
        defer { lock.unlock() }

        let identifier = renderer.identifier
        let panelType = renderer.panelType
        let entry = PanelEntry(
            identifier: identifier,
            panelType: panelType,
            renderer: AnyPanelRenderer(renderer),
            priority: priority
        )

        panels[identifier] = entry

        if panelsByType[panelType] == nil {
            panelsByType[panelType] = []
        }
        panelsByType[panelType]?.append(identifier)
    }

    public func unregister(identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        if let entry = panels.removeValue(forKey: identifier) {
            panelsByType[entry.panelType]?.removeAll { $0 == identifier }
        }
    }

    public func get(identifier: String) -> AnyPanelRenderer? {
        lock.lock()
        defer { lock.unlock() }

        return panels[identifier]?.renderer
    }

    public func getAll(type: PanelType) -> [AnyPanelRenderer] {
        lock.lock()
        defer { lock.unlock() }

        guard let identifiers = panelsByType[type] else {
            return []
        }

        return identifiers.compactMap { panels[$0]?.renderer }
            .sorted { panel1, panel2 in
                let entry1 = panels.values.first { $0.renderer.identifier == panel1.identifier }
                let entry2 = panels.values.first { $0.renderer.identifier == panel2.identifier }
                return (entry1?.priority ?? 0) > (entry2?.priority ?? 0)
            }
    }

    public func getAll() -> [AnyPanelRenderer] {
        lock.lock()
        defer { lock.unlock() }

        return panels.values
            .sorted { $0.priority > $1.priority }
            .map { $0.renderer }
    }

    public func list() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        return Array(panels.keys).sorted()
    }

    public func getByType(_ panelType: PanelType) -> AnyPanelRenderer? {
        lock.lock()
        defer { lock.unlock() }

        if let identifiers = panelsByType[panelType], let firstId = identifiers.first {
            return panels[firstId]?.renderer
        }
        return nil
    }

    public func asComponentTree() -> TUIRenderable? {
        lock.lock()
        defer { lock.unlock() }

        let allPanels = panels.values
            .sorted { $0.priority > $1.priority }
            .map { $0.renderer }

        guard !allPanels.isEmpty else { return nil }

        return ContainerComponent(
            id: "registry-root",
            children: []
        )
    }
}
