import Foundation

public final class TUIRenderer: TUIRendererProtocol, @unchecked Sendable {
    private let colorManager: ColorManagerProtocol
    private let commandBarRenderer: CommandBarRenderer
    private let esc = "\u{001B}["

    public init(colorManager: ColorManagerProtocol = ColorManager()) {
        self.colorManager = colorManager
        self.commandBarRenderer = CommandBarRenderer(colorManager: colorManager)
    }

    public func renderInitialState() async {
        await clearScreen()
        print(colorManager.bold("SmartVestor") + "  \(colorManager.green("CONNECTED"))")
        print("")
        let now = ISO8601DateFormatter().string(from: Date())
        print("\(colorManager.dim("Connection established: \(now)"))")
        print("\(colorManager.dim("Update frequency: ~60s (heartbeat)"))")
        print("")
        print(colorManager.bold("Status"))
        print("  State: \(colorManager.dim("Waiting for first update..."))")
        print("  Mode: \(colorManager.dim("-"))")
        print("  Total Value: \(colorManager.dim("$-"))")
        print("")
        print(colorManager.bold("Balances"))
        print("")
        let hAsset = "ASSET".padding(toLength: 8, withPad: " ", startingAt: 0)
        let hVal = "VALUE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hQty = "QUANTITY".padding(toLength: 14, withPad: " ", startingAt: 0)
        let hPrice = "PRICE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hW = "%".padding(toLength: 6, withPad: " ", startingAt: 0)
        let hUpd = "UPDATED".padding(toLength: 20, withPad: " ", startingAt: 0)
        let header = "\(hAsset)  \(hVal)  \(hQty)  \(hPrice)  \(hW)  \(hUpd)"
        print(header)
        print(String(repeating: "-", count: header.count))
        print("\(colorManager.dim("Waiting for data..."))")
        print("")
        print(colorManager.bold("Recent Activity"))
        print("  \(colorManager.dim("No trades yet"))")
        print("")
        print("\(colorManager.dim("Initial snapshot shown; live values update every cycle."))")
        print("")
        print(commandBarRenderer.renderDefaultCommands())
    }

    public func renderUpdate(_ update: TUIUpdate) async {
        await clearScreen()
        let running = update.state.isRunning
        let mode = update.state.mode.rawValue
        let headerColor = running ? colorManager.green : colorManager.red
        let statusText = running ? "RUNNING" : "STOPPED"
        let ts = ISO8601DateFormatter().string(from: update.timestamp)
        print("\(colorManager.bold("SmartVestor"))  \(headerColor(statusText))  mode=\(mode)  seq=\(update.sequenceNumber)")
        print("as of \(ts)")
        print("\(colorManager.dim("Initial snapshot shown; live values update every cycle."))")
        print("")
        let total = String(format: "%.2f", update.data.totalPortfolioValue)
        let err = update.data.errorCount
        let cb = update.data.circuitBreakerOpen
        let cbStr = cb ? colorManager.red("OPEN") : colorManager.green("CLOSED")
        print("Total Value: $\(total)   Errors: \(err)   Circuit Breaker: \(cbStr)")
        if let last = update.data.lastExecutionTime {
            let s = ISO8601DateFormatter().string(from: last)
            print("Last Exec: \(s)")
        }
        print("")
        await renderBalances(update.data.balances)
        await renderRecentTrades(update.data.recentTrades)
        print("")
        print(commandBarRenderer.renderDefaultCommands(isRunning: update.state.isRunning))
    }

    public nonisolated func renderUpdateWithPrices(_ update: TUIUpdate, prices: [String: Double]) async {
        await clearScreen()
        let running = update.state.isRunning
        let mode = update.state.mode.rawValue
        let headerColor = running ? colorManager.green : colorManager.red
        let statusText = running ? "RUNNING" : "STOPPED"
        let ts = ISO8601DateFormatter().string(from: update.timestamp)
        print("\(colorManager.bold("SmartVestor"))  \(headerColor(statusText))  mode=\(mode)  seq=\(update.sequenceNumber)")
        print("as of \(ts)")
        print("")
        var values: [String: Double] = [:]
        for h in update.data.balances {
            let price = prices[h.asset] ?? 0
            values[h.asset] = h.available * price
        }
        let total = max(0.000001, values.values.reduce(0, +))
        let totalStr = String(format: "%.2f", values.values.reduce(0, +))
        let err = update.data.errorCount
        let cb = update.data.circuitBreakerOpen
        let cbStr = cb ? colorManager.red("OPEN") : colorManager.green("CLOSED")
        print("Total Value: $\(totalStr)   Errors: \(err)   Circuit Breaker: \(cbStr)")
        if let last = update.data.lastExecutionTime {
            let s = ISO8601DateFormatter().string(from: last)
            print("Last Exec: \(s)")
        }
        print("")
        await renderBalancesWithPrices(update.data.balances, prices: prices, values: values, total: total)
        await renderRecentTrades(update.data.recentTrades)
        print("")
        print(commandBarRenderer.renderDefaultCommands(isRunning: update.state.isRunning))
    }

    public func clearScreen() async {
        print("\(esc)H\(esc)J", terminator: "")
    }

    private func renderBalances(_ balances: [Holding]) async {
        print(colorManager.bold("Balances"))
        print("")
        let rows = balances.filter { $0.available > 0 }.sorted { a, b in a.available > b.available }
        let hAsset = "ASSET".padding(toLength: 8, withPad: " ", startingAt: 0)
        let hVal = "VALUE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hQty = "QUANTITY".padding(toLength: 14, withPad: " ", startingAt: 0)
        let hPrice = "PRICE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hW = "%".padding(toLength: 6, withPad: " ", startingAt: 0)
        let hUpd = "UPDATED".padding(toLength: 20, withPad: " ", startingAt: 0)
        let header = "\(hAsset)  \(hVal)  \(hQty)  \(hPrice)  \(hW)  \(hUpd)"
        print(header)
        print(String(repeating: "-", count: header.count))
        let iso = ISO8601DateFormatter()
        if rows.isEmpty {
            print("\(colorManager.dim("No balances found"))")
        } else {
            for h in rows {
                let qtyStr = String(format: "%.6f", h.available).padding(toLength: 14, withPad: " ", startingAt: 0)
                let priceStr = "loading...".padding(toLength: 12, withPad: " ", startingAt: 0)
                let valStr = "-".padding(toLength: 12, withPad: " ", startingAt: 0)
                let wStr = "-".padding(toLength: 6, withPad: " ", startingAt: 0)
                let upd = iso.string(from: h.updatedAt).padding(toLength: 20, withPad: " ", startingAt: 0)
                let asset = h.asset.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("\(asset)  \(colorManager.dim(valStr))  \(qtyStr)  \(colorManager.dim(priceStr))  \(colorManager.dim(wStr))  \(upd)")
            }
        }
        print("")
    }

    private func renderBalancesWithPrices(_ balances: [Holding], prices: [String: Double], values: [String: Double], total: Double) async {
        print(colorManager.bold("Balances"))
        print("")
        let rows = balances.filter { $0.available > 0 }.sorted { a, b in
            let valA = values[a.asset] ?? 0
            let valB = values[b.asset] ?? 0
            return valA > valB
        }
        let hAsset = "ASSET".padding(toLength: 8, withPad: " ", startingAt: 0)
        let hVal = "VALUE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hQty = "QUANTITY".padding(toLength: 14, withPad: " ", startingAt: 0)
        let hPrice = "PRICE".padding(toLength: 12, withPad: " ", startingAt: 0)
        let hW = "%".padding(toLength: 6, withPad: " ", startingAt: 0)
        let hUpd = "UPDATED".padding(toLength: 20, withPad: " ", startingAt: 0)
        let header = "\(hAsset)  \(hVal)  \(hQty)  \(hPrice)  \(hW)  \(hUpd)"
        print(header)
        print(String(repeating: "-", count: header.count))
        let iso = ISO8601DateFormatter()
        for h in rows {
            let price = prices[h.asset] ?? 0
            let value = values[h.asset] ?? 0
            let weight = value / total * 100
            let qtyStr = String(format: "%.6f", h.available).padding(toLength: 14, withPad: " ", startingAt: 0)
            let priceStr = (price > 0 ? String(format: "%.6f", price) : "-").padding(toLength: 12, withPad: " ", startingAt: 0)
            let valStr = String(format: "%.2f", value).padding(toLength: 12, withPad: " ", startingAt: 0)
            let wStr = String(format: "%5.1f", weight).padding(toLength: 6, withPad: " ", startingAt: 0)
            let upd = iso.string(from: h.updatedAt).padding(toLength: 20, withPad: " ", startingAt: 0)
            let asset = h.asset.padding(toLength: 8, withPad: " ", startingAt: 0)
            print("\(asset)  \(valStr)  \(qtyStr)  \(priceStr)  \(wStr)  \(upd)")
        }
        print("")
    }

    private func renderRecentTrades(_ trades: [InvestmentTransaction]) async {
        if !trades.isEmpty {
            print(colorManager.bold("Recent Trades"))
            for tx in trades {
                let p = String(format: "%.6f", tx.price)
                let q = String(format: "%.6f", tx.quantity)
                print("\(tx.type.rawValue.uppercased()) \(tx.asset) qty=\(q) @ \(p) ex=\(tx.exchange)")
            }
        } else {
            print("\(colorManager.dim("No recent trades"))")
        }
        print("")
    }
}
