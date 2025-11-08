import Foundation
@testable import SmartVestor

func makeStatusOnlyTree(update: TUIUpdate = makeSampleUpdate()) async -> TUIRenderable {
    let registry = makeTestRegistry()
    let bridge = TUIUpdateBridge(panelRegistry: registry)

    let layouts = [
        PanelType.status: PanelLayout(x: 0, y: 0, width: 80, height: 8)
    ]

    let ctx = BridgeContext(
        visiblePanels: [.status],
        layouts: layouts,
        borderStyle: .unicode,
        unicodeSupported: true
    )

    return await bridge.createComponentTree(from: update, context: ctx)
}

func makeAllPanelsTree(update: TUIUpdate = makeSampleUpdate(), prices: [String: Double]? = samplePrices()) async -> TUIRenderable {
    let registry = makeTestRegistry()
    let bridge = TUIUpdateBridge(panelRegistry: registry)

    let layouts = [
        PanelType.status: PanelLayout(x: 0, y: 0, width: 120, height: 8),
        PanelType.balances: PanelLayout(x: 0, y: 8, width: 120, height: 10),
        PanelType.activity: PanelLayout(x: 0, y: 18, width: 120, height: 10),
        PanelType.price: PanelLayout(x: 0, y: 28, width: 120, height: 8),
        PanelType.swap: PanelLayout(x: 0, y: 36, width: 120, height: 4)
    ]

    let ctx = BridgeContext(
        visiblePanels: [.status, .balances, .activity, .price, .swap],
        layouts: layouts,
        borderStyle: .unicode,
        unicodeSupported: true
    )

    return await bridge.createComponentTree(from: update, context: ctx, prices: prices)
}

private func makeTestRegistry() -> PanelRegistry {
    let registry = PanelRegistry()
    registry.register(StatusPanelRenderer())
    registry.register(BalancePanelRenderer())
    registry.register(ActivityPanelRenderer())
    registry.register(PricePanelRenderer())
    registry.register(SwapPanelRenderer())
    return registry
}

func makeSampleUpdate() -> TUIUpdate {
    let state = AutomationState(
        isRunning: false,
        mode: .continuous,
        startedAt: nil,
        lastExecutionTime: nil,
        nextExecutionTime: nil,
        pid: nil
    )

    let data = TUIData(
        recentTrades: [],
        balances: [],
        circuitBreakerOpen: false,
        lastExecutionTime: nil,
        nextExecutionTime: nil,
        totalPortfolioValue: 0,
        errorCount: 0
    )

    return TUIUpdate(
        type: .heartbeat,
        state: state,
        data: data,
        sequenceNumber: 0
    )
}

func samplePrices() -> [String: Double] {
    [
        "BTC": 45000.0,
        "ETH": 3000.0,
        "USDC": 1.0
    ]
}
