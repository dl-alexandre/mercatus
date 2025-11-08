import Foundation
import Core

public struct BridgeContext: Sendable {
    public let visiblePanels: [PanelType]
    public let layouts: [PanelType: PanelLayout]
    public let borderStyle: BorderStyle
    public let unicodeSupported: Bool

    public init(
        visiblePanels: [PanelType],
        layouts: [PanelType: PanelLayout],
        borderStyle: BorderStyle,
        unicodeSupported: Bool
    ) {
        self.visiblePanels = visiblePanels
        self.layouts = layouts
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
    }
}

public final class TUIUpdateBridge: @unchecked Sendable {
    private let layoutManager: LayoutManagerProtocol
    private let colorManager: ColorManagerProtocol
    private let panelRegistry: PanelRegistry

    public init(
        layoutManager: LayoutManagerProtocol = LayoutManager.shared,
        colorManager: ColorManagerProtocol = ColorManager(),
        panelRegistry: PanelRegistry
    ) {
        self.layoutManager = layoutManager
        self.colorManager = colorManager
        self.panelRegistry = panelRegistry
    }

    public func createComponentTree(
        from update: TUIUpdate,
        context: BridgeContext,
        prices: [String: Double]? = nil,
        focus: PanelFocus? = nil
    ) async -> TUIRenderable {
        let visiblePanelSet = Set(context.visiblePanels)
        let layouts = context.layouts

        let borderStyle = context.borderStyle
        let unicodeSupported = context.unicodeSupported

        let sortedPanels: [(PanelType, PanelLayout)] = layouts
            .filter { panelType, _ in
                visiblePanelSet.contains(panelType) ||
                (panelType == .balance && visiblePanelSet.contains(.balances)) ||
                (panelType == .balances && visiblePanelSet.contains(.balance))
            }
            .sorted { $0.value.y < $1.value.y }
            .map { ($0.key, $0.value) }

        var panelComponents: [TUIRenderable] = []
        var renderedBalancePanel = false
        var panelIds: Set<AnyHashable> = []

        if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
            print("[TUI PERF] Building tree for \(sortedPanels.count) panels")
        }

        for (panelType, layout) in sortedPanels {
            if (panelType == .balance || panelType == .balances) && renderedBalancePanel {
                if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
                    print("[TUI PERF] Skipping duplicate balance panel: \(panelType)")
                }
                continue
            }

            if panelType == .balance || panelType == .balances {
                renderedBalancePanel = true
            }

            let panel = panelRegistry.getByType(panelType)
            if panel == nil && ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
                print("[TUI PERF] No panel found for type: \(panelType)")
            }
            guard let panel = panel else { continue }

            let isFocused = focus?.panelType == panelType

            if panelType == .status && TUIFeatureFlags.isStatusPanelDeclarative {
                let statusView = StatusPanelView(
                    update: update,
                    layout: layout,
                    colorManager: colorManager,
                    borderStyle: borderStyle,
                    unicodeSupported: unicodeSupported,
                    isFocused: isFocused
                )
                let id = statusView.id
                panelIds.insert(id)
                panelComponents.append(statusView)
            } else if (panelType == .balance || panelType == .balances) && TUIFeatureFlags.isBalancesPanelDeclarative {
                let balancesView = BalancesView(
                    update: update,
                    layout: layout,
                    colorManager: colorManager,
                    borderStyle: borderStyle,
                    unicodeSupported: unicodeSupported,
                    isFocused: isFocused,
                    prices: prices
                )
                balancesView.buildRows()
                let id = balancesView.id
                panelIds.insert(id)
                panelComponents.append(balancesView)
            } else if panelType == .activity && TUIFeatureFlags.isActivityPanelDeclarative {
                let activityView = ActivityView(
                    update: update,
                    layout: layout,
                    colorManager: colorManager,
                    borderStyle: borderStyle,
                    unicodeSupported: unicodeSupported,
                    isFocused: isFocused
                )
                activityView.buildRows()
                let id = activityView.id
                panelIds.insert(id)
                panelComponents.append(activityView)
            } else if panelType == .price && TUIFeatureFlags.isPricePanelDeclarative {
                let priceView = PriceView(
                    update: update,
                    layout: layout,
                    colorManager: colorManager,
                    borderStyle: borderStyle,
                    unicodeSupported: unicodeSupported,
                    isFocused: isFocused
                )
                let id = priceView.id
                panelIds.insert(id)
                panelComponents.append(priceView)
            } else {
                let renderedPanel: RenderedPanel
                if panel.identifier == "balance", let prices = prices {
                    let balanceRenderer = BalancePanelRenderer()
                    renderedPanel = await balanceRenderer.render(
                        input: update,
                        layout: layout,
                        colorManager: colorManager,
                        borderStyle: borderStyle,
                        unicodeSupported: unicodeSupported,
                        isFocused: isFocused,
                        prices: prices
                    )
                } else {
                    renderedPanel = await panel.render(
                        input: update,
                        layout: layout,
                        colorManager: colorManager,
                        borderStyle: borderStyle,
                        unicodeSupported: unicodeSupported
                    )
                }

                let adapter = PanelAdapter(
                    panelType: panelType,
                    renderedLines: renderedPanel.lines,
                    layout: layout
                )

                    let adapterId = adapter.id
                panelIds.insert(adapterId)
                panelComponents.append(adapter)
            }
        }

        if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
            let panelIdsList = panelComponents.map { "\($0.id)" }
            print("[TUI PERF] Panel IDs: \(panelIds.count) unique, expected ~\(Set([PanelType.status, .balances, .activity, .price]).count), ids: \(panelIdsList)")
        }

        return ContainerComponent(
            id: "root" as AnyHashable,
            children: panelComponents
        )
    }
}
