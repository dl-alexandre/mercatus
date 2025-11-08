import Foundation
import Core
#if os(macOS) || os(Linux)
import Darwin
#endif

public protocol EnhancedTUIRendererProtocol: TUIRendererProtocol {
    func renderPanels(_ update: TUIUpdate, prices: [String: Double]?, focus: PanelFocus?) async -> [String]
    func renderPanels(_ update: TUIUpdate, focus: PanelFocus?) async -> [String]
}

private final actor FramePump {
    private var inFlight = false
    private var pending = false
    private var queued: (TUIUpdate?, [String: Double]?, PanelFocus?) = (nil, nil, nil)

    func enqueue(
        update: TUIUpdate?,
        prices: [String: Double]?,
        focus: PanelFocus?,
        renderer: EnhancedTUIRenderer
    ) async {
        let isRendering = await renderer.getRendering()
        if isRendering {
            #if DEBUG
            let msg = "[FramePump] Blocked enqueue during render (rendering=true)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            #endif
            queued = (update ?? queued.0, prices ?? queued.1, focus ?? queued.2)
            pending = true
            return
        }

        queued = (update ?? queued.0, prices ?? queued.1, focus ?? queued.2)
        pending = true

        guard !inFlight else {
            #if DEBUG
            if TUIFeatureFlags.isDebugOverlayEnabled {
                let msg = "[FramePump] Coalescing render request (inFlight=true)\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
            #endif
            return
        }

        inFlight = true
        defer {
            inFlight = false
            #if DEBUG
            if TUIFeatureFlags.isDebugOverlayEnabled {
                let msg = "[FramePump] exit\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
            #endif
        }

        var iterations = 0
        while pending {
            pending = false
            iterations &+= 1
            await renderer.renderFrameOnce(queued.0, prices: queued.1, focus: queued.2)
            try? await Task.sleep(nanoseconds: 1_000_000)
            if iterations > 128 {
                #if DEBUG
                let msg = "[FramePump] ERROR: Loop count exceeded 128, breaking\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                #endif
                break
            }
        }
    }
}

public actor EnhancedTUIRenderer: EnhancedTUIRendererProtocol {
    private let colorManager: ColorManagerProtocol
    private let commandBarRenderer: CommandBarRenderer
    private let layoutManager: LayoutManagerProtocol
    private let panelRegistry: PanelRegistry
    private let performanceMonitor: Core.PerformanceMonitor?
    private let toggleManager: PanelToggleManager
    private let scrollState: PanelScrollState
    private let priceSortManager: PriceSortManager
    private let updateRateLimiter: UpdateRateLimiter
    private var logsRenderer: LogsPanelRenderer?
    private let esc = "\u{001B}["
    private var cachedTerminalSize: TerminalSize?
    private var lastRenderedFrame: [String]?
    private let coalescer = FrameCoalescer()
    private var lastKnownPrices: [String: Double] = [:]
    private let pump = FramePump()
    private var lastUpdate: TUIUpdate?
    private var isRenderingInitial = false
    private var rendering = false
    private struct HelpOverlayState {
        var lines: [String]
        var scrollOffset: Int
    }
    private var helpOverlayState: HelpOverlayState?

    public init(
        colorManager: ColorManagerProtocol = ColorManager(),
        layoutManager: LayoutManagerProtocol = LayoutManager.shared,
        panelRegistry: PanelRegistry? = nil,
        performanceMonitor: Core.PerformanceMonitor? = nil,
        toggleManager: PanelToggleManager? = nil,
        scrollState: PanelScrollState? = nil,
        priceSortManager: PriceSortManager? = nil,
        updateRateLimiter: UpdateRateLimiter? = nil
    ) {
        self.colorManager = colorManager
        self.commandBarRenderer = CommandBarRenderer(colorManager: colorManager)
        self.layoutManager = layoutManager
        self.performanceMonitor = performanceMonitor
        self.toggleManager = toggleManager ?? PanelToggleManager()
        self.scrollState = scrollState ?? PanelScrollState()
        self.priceSortManager = priceSortManager ?? PriceSortManager()
        self.updateRateLimiter = updateRateLimiter ?? UpdateRateLimiter(minInterval: 0.1)

        let registry = panelRegistry ?? PanelRegistry()
        if panelRegistry == nil {
            registry.register(StatusPanelRenderer())
            registry.register(BalancePanelRenderer())
            registry.register(ActivityPanelRenderer())
            registry.register(PricePanelRenderer())
            registry.register(SwapPanelRenderer())
            let logsPanel = LogsPanelRenderer()
            self.logsRenderer = logsPanel
            registry.register(logsPanel)
        }
        self.panelRegistry = registry
    }

    public func renderInitialState() async {
        await renderInitialState(persistence: nil)
    }

    public func renderInitialState(persistence: PersistenceProtocol?) async {
        guard !Task.isCancelled else { return }

        if isRenderingInitial {
            if TUIFeatureFlags.isDebugOverlayEnabled {
                let msg = "[Render] renderInitialState already in progress, skipping\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
            return
        }

        isRenderingInitial = true
        defer { isRenderingInitial = false }

        let initialState = AutomationState(
            isRunning: false,
            mode: .continuous,
            startedAt: nil,
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: nil
        )

        var recentTrades: [InvestmentTransaction] = []
        var balances: [Holding] = []
        if let persistence = persistence {
            do {
                recentTrades = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 10)
                balances = try persistence.getAllAccounts()
            } catch {
            }
        }

        let initialData = TUIData(
            recentTrades: recentTrades,
            balances: balances,
            circuitBreakerOpen: false,
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            totalPortfolioValue: 0,
            errorCount: 0
        )

        let initialUpdate = TUIUpdate(
            type: .heartbeat,
            state: initialState,
            data: initialData,
            sequenceNumber: 0
        )

        guard !Task.isCancelled else { return }
        lastUpdate = initialUpdate
        await scheduleRender(update: initialUpdate, prices: nil, focus: nil)
    }

    private func populateLogs() async {
        guard let logsRenderer = logsRenderer else { return }

        var logLines: [String] = []

        #if os(macOS) || os(Linux)
        let logPaths = [
            "/tmp/smartvestor-automation.log",
            "/tmp/smartvestor.log",
            "smartvestor.log",
            ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"] ?? ""
        ].filter { !$0.isEmpty }

        for logPath in logPaths {
            if let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) {
                let allLines = logContent.components(separatedBy: .newlines)
                let recentLines = Array(allLines.suffix(15))
                logLines.append(contentsOf: recentLines.filter { !$0.isEmpty })
                break
            }
        }
        #endif

        if logLines.isEmpty {
            logLines.append("No log file found")
        }

        logsRenderer.setLogEntries(logLines)
    }

    public func renderUpdate(_ update: TUIUpdate) async {
        guard !Task.isCancelled else { return }

        let pricesDict = update.data.prices
        let pricesToUse: [String: Double]
        if !pricesDict.isEmpty {
            pricesToUse = pricesDict
            lastKnownPrices = pricesDict
        } else if !lastKnownPrices.isEmpty {
            pricesToUse = lastKnownPrices
        } else {
            pricesToUse = [:]
        }

        lastUpdate = update
        await scheduleRender(update: update, prices: pricesToUse, focus: nil)
    }

    public nonisolated func renderUpdateWithPrices(_ update: TUIUpdate, prices: [String: Double]) async {
        await scheduleRender(update: update, prices: prices, focus: nil)
    }

    public func scheduleRender(update: TUIUpdate?, prices: [String: Double]?, focus: PanelFocus?) async {
        if rendering {
            #if DEBUG
            let msg = "[scheduleRender] Blocked during render (rendering=true)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            #endif
            return
        }
        await updateRateLimiter.throttle {
            await self.pump.enqueue(update: update, prices: prices, focus: focus, renderer: self)
        }
    }

    nonisolated func safeScheduleFromCallback(_ update: TUIUpdate?, _ prices: [String: Double]?, _ focus: PanelFocus?) {
        Task { [weak self] in
            await self?.scheduleRender(update: update, prices: prices, focus: focus)
        }
    }

    private func recordPerformanceMetrics(renderTimeMs: Double) async {
        if let monitor = performanceMonitor {
            await monitor.recordRenderTime(renderTimeMs: renderTimeMs)
            await monitor.recordFrame()
        }
    }

    public func renderPanels(_ update: TUIUpdate, prices: [String: Double]?, focus: PanelFocus?) async -> [String] {
        let terminalSize = detectAndCacheTerminalSize()

        var visiblePanels = await toggleManager.getVisiblePanels()
        if visiblePanels.isEmpty {
            do {
                try await toggleManager.setVisibility(.status, visible: true)
                try await toggleManager.setVisibility(.balances, visible: true)
                try await toggleManager.setVisibility(.activity, visible: true)
            } catch {
            }
            visiblePanels = await toggleManager.getVisiblePanels()
            if visiblePanels.isEmpty {
                var frame: [String] = []
                let headerLines = renderHeader(update: update)
                frame.append(contentsOf: headerLines)
                frame.append("")
                frame.append("⚠️  No panels available")
                frame.append("")
                return frame
            }
        }

        let visiblePanelSet = Set(visiblePanels)
        let layouts = layoutManager.calculateLayout(terminalSize: terminalSize, visiblePanels: visiblePanelSet)

        guard !layouts.isEmpty else {
            var frame: [String] = []
            let headerLines = renderHeader(update: update)
            frame.append(contentsOf: headerLines)
            frame.append("")
            frame.append("⚠️  No panels could be laid out (terminal may be too small)")
            frame.append("")
            return frame
        }

        let selectedPanel = await toggleManager.getSelectedPanel()

        let sortedPanels: [(PanelType, PanelLayout)] = layouts
            .filter { panelType, layout in
                guard layout.isValid else { return false }
                return visiblePanelSet.contains(panelType) ||
                       (panelType == .balance && visiblePanelSet.contains(.balances)) ||
                       (panelType == .balances && visiblePanelSet.contains(.balance))
            }
            .sorted { lhs, rhs in
                if lhs.value.y != rhs.value.y {
                    return lhs.value.y < rhs.value.y
                }
                return lhs.value.x < rhs.value.x
            }
            .map { ($0.key, $0.value) }

        var grid: [[String]] = Array(repeating: Array(repeating: " ", count: terminalSize.width), count: terminalSize.height)

        let headerLines = renderHeader(update: update)
        for (idx, headerLine) in headerLines.enumerated() {
            if idx < grid.count {
                var charIdx = 0
                var lineIdx = headerLine.startIndex
                var currentCell = ""

                while charIdx < headerLine.count && lineIdx < headerLine.endIndex {
                    if charIdx < grid[idx].count {
                        let char = headerLine[lineIdx]
                        if char == "\u{001B}" {
                            var ansiEnd = headerLine.index(after: lineIdx)
                            while ansiEnd < headerLine.endIndex {
                                if headerLine[ansiEnd] >= "@" && headerLine[ansiEnd] <= "~" {
                                    ansiEnd = headerLine.index(after: ansiEnd)
                                    let ansiSeq = String(headerLine[lineIdx..<ansiEnd])
                                    currentCell += ansiSeq
                                    lineIdx = ansiEnd
                                    break
                                }
                                ansiEnd = headerLine.index(after: ansiEnd)
                            }
                        } else {
                            currentCell += String(char)
                            if currentCell.isEmpty {
                                grid[idx][charIdx] = " "
                            } else {
                                grid[idx][charIdx] = currentCell
                                currentCell = ""
                            }
                            charIdx += 1
                            lineIdx = headerLine.index(after: lineIdx)
                        }
                    } else {
                        break
                    }
                }
            }
        }

        var renderedBalancePanel = false

        for (panelType, layout) in sortedPanels {
            if (panelType == .balance || panelType == .balances) && renderedBalancePanel {
                continue
            }

            let isSelected = selectedPanel == panelType ||
                           (panelType == .balance && selectedPanel == .balances) ||
                           (panelType == .balances && selectedPanel == .balance)
            let focusState = focus?.panelType == panelType || isSelected

            if TUIFeatureFlags.isDebugTreeEnabled {
                let msg = "[Focus] Panel \(panelType) isSelected=\(isSelected) focusState=\(focusState) selectedPanel=\(String(describing: selectedPanel))\n"
                #if os(macOS) || os(Linux)
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                #else
                print(msg, to: &FileHandle.standardError)
                #endif
            }
            var panels = panelRegistry.getAll(type: panelType)

            if panels.isEmpty && panelType == .balances {
                panels = panelRegistry.getAll(type: .balance)
            }

            if panels.isEmpty && panelType == .balance {
                panels = panelRegistry.getAll(type: .balances)
            }

            if let panel = panels.first {
                let rendered = await renderPanel(
                    panel: panel,
                    update: update,
                    layout: layout,
                    isFocused: focusState,
                    prices: prices
                )

                let contentLines = rendered.lines.filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return false }
                    let withoutBorder = trimmed.replacingOccurrences(of: "│", with: "").replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "─", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "║", with: "").replacingOccurrences(of: "═", with: "").replacingOccurrences(of: "┌", with: "").replacingOccurrences(of: "┐", with: "").replacingOccurrences(of: "└", with: "").replacingOccurrences(of: "┘", with: "").trimmingCharacters(in: .whitespaces)
                    return !withoutBorder.isEmpty
                }

                if rendered.lines.isEmpty || (rendered.hasBorder && contentLines.count <= 1) {
                    let errorMsg = "⚠️  Panel '\(panel.identifier)' failed to render (empty output)"
                    let availableWidth = max(10, max(0, layout.width - 4))
                    let trimmedMsg = errorMsg.count > availableWidth
                        ? String(errorMsg.prefix(max(0, availableWidth - 3))) + "..."
                        : errorMsg
                    let paddedMsg = trimmedMsg + String(repeating: " ", count: max(0, availableWidth - trimmedMsg.count))
                    let errorLine = "│ \(paddedMsg) │"
                    writeToGrid(&grid, lines: [errorLine], at: layout)
                } else {
                    if TUIFeatureFlags.isDebugOverlayEnabled {
                        let horizontalPanelTypes: Set<PanelType> = [.activity, .price, .swap]
                        if horizontalPanelTypes.contains(panelType) {
                            let msg = "[Grid] Writing \(rendered.lines.count) lines for horizontal panel \(panelType) at x=\(layout.x) width=\(layout.width)\n"
                            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                        }
                    }
                    writeToGrid(&grid, lines: rendered.lines, at: layout)
                }

                if panelType == .balance || panelType == .balances {
                    renderedBalancePanel = true
                }
            }
        }

        let selectedPanelForCommands = selectedPanel
        let commandLine = commandBarRenderer.renderContextSensitiveCommands(for: selectedPanelForCommands, isRunning: update.state.isRunning, highlightedKey: nil)

        let footerStartY = terminalSize.height - 1

        if footerStartY >= 0 && footerStartY < grid.count {
            let commandChars = Array(commandLine)
            for (idx, char) in commandChars.enumerated() {
                if idx < grid[footerStartY].count {
                    grid[footerStartY][idx] = String(char)
                }
            }
        }

        var frame: [String] = []
        for row in grid {
            let rowString = row.joined()
            let truncated = String(rowString.prefix(terminalSize.width))
            frame.append(truncated)
        }

        return frame
    }

    public func renderPanels(_ update: TUIUpdate, focus: PanelFocus?) async -> [String] {
        return await renderPanels(update, prices: nil, focus: focus)
    }

    private func renderPanel(
        panel: AnyPanelRenderer,
        update: TUIUpdate,
        layout: PanelLayout,
        isFocused: Bool,
        prices: [String: Double]?
    ) async -> RenderedPanel {
        let borderStyle: BorderStyle = colorManager.supportsUnicode ? .unicode : .ascii

        if panel.identifier == "status" {
            let statusRenderer = StatusPanelRenderer()
            return await statusRenderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused
            )
        } else if panel.identifier == "balance" {
            let balanceRenderer = BalancePanelRenderer()
            let scrollPos = await scrollState.getScrollPosition(for: .balances)
            return await balanceRenderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused,
                prices: prices,
                scrollOffset: scrollPos
            )
        } else if panel.identifier == "activity" {
            let activityRenderer = ActivityPanelRenderer()
            let scrollPos = await scrollState.getScrollPosition(for: .activity)
            return await activityRenderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused,
                scrollOffset: scrollPos
            )
        } else if panel.identifier == "price" {
            let priceRenderer = PricePanelRenderer()
            let scrollPos = await scrollState.getScrollPosition(for: .price)
            return await priceRenderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused,
                prices: prices,
                scrollOffset: scrollPos,
                priceSortManager: priceSortManager
            )
        } else if panel.identifier == "swap" {
            let swapRenderer = SwapPanelRenderer()
            let scrollPos = await scrollState.getScrollPosition(for: .swap)
            return await swapRenderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused,
                scrollOffset: scrollPos
            )
        } else if panel.identifier == "logs" {
            let renderer = logsRenderer ?? LogsPanelRenderer()
            let scrollPos = await scrollState.getScrollPosition(for: .logs)
            return await renderer.render(
                input: update,
                layout: layout,
                colorManager: colorManager,
                borderStyle: borderStyle,
                unicodeSupported: colorManager.supportsUnicode,
                isFocused: isFocused,
                scrollOffset: scrollPos
            )
        }

        return await panel.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: borderStyle,
            unicodeSupported: colorManager.supportsUnicode
        )
    }

    private func calculateValues(update: TUIUpdate, prices: [String: Double]?) -> [String: Double] {
        var values: [String: Double] = [:]

        guard let prices = prices else {
            return values
        }

        for holding in update.data.balances {
            let price = prices[holding.asset] ?? 0
            values[holding.asset] = holding.available * price
        }

        return values
    }

    private func renderHeader(update: TUIUpdate? = nil) -> [String] {
        var lines: [String] = []

        if let update = update {
            let running = update.state.isRunning
            let mode = update.state.mode.rawValue
            let headerColor = running ? colorManager.green : colorManager.red
            let statusText = running ? "RUNNING" : "STOPPED"
            let ts = ISO8601DateFormatter().string(from: update.timestamp)
            lines.append("\(colorManager.bold("SmartVestor"))  \(headerColor(statusText))  mode=\(mode)  seq=\(update.sequenceNumber)")
            lines.append("as of \(ts)")
        } else {
            lines.append(colorManager.bold("SmartVestor") + "  \(colorManager.green("CONNECTED"))")
            let now = ISO8601DateFormatter().string(from: Date())
            lines.append("\(colorManager.dim("Connection established: \(now)"))")
        }

        return lines
    }

    public func clearScreen() async {
        let isTTY = await Runtime.renderBus.isOutputTTY()
        guard isTTY else { return }
        await Runtime.renderBus.write("\(esc)H\(esc)2J\(esc)[?25l")
    }


    private func detectAndCacheTerminalSize() -> TerminalSize {
        let detected = layoutManager.detectTerminalSize()
        cachedTerminalSize = detected
        return detected
    }

    public func invalidateCachedTerminalSize() async {
        cachedTerminalSize = nil
    }

    public func getTerminalSize() async -> TerminalSize {
        return cachedTerminalSize ?? detectAndCacheTerminalSize()
    }

    private func applyHelpOverlay(
        to frame: [String],
        overlay: HelpOverlayState,
        terminalSize: TerminalSize
    ) -> [String] {
        let rows = max(terminalSize.height, 1)
        let cols = max(terminalSize.width, 1)

        guard !overlay.lines.isEmpty, rows > 2, cols > 4 else {
            return frame
        }

        let availableContentLines = max(rows - 4, 1)
        let maxVisibleLines = min(overlay.lines.count, availableContentLines)
        let maxScroll = max(overlay.lines.count - maxVisibleLines, 0)
        // CRITICAL: Clamp offset to valid range to prevent scrolling out of bounds
        let clampedOffset = max(0, min(overlay.scrollOffset, maxScroll))

        // Ensure we don't try to access beyond the array bounds
        let safeStartIndex = clampedOffset
        let safeEndIndex = min(safeStartIndex + maxVisibleLines, overlay.lines.count)
        guard safeStartIndex < overlay.lines.count && safeEndIndex > safeStartIndex else {
            // Invalid range, return original frame
            return frame
        }
        let visibleLines = Array(overlay.lines[safeStartIndex..<safeEndIndex])

        // CRITICAL: Use the actual number of visible lines for dialog height calculation
        // This ensures alignment is correct even when scrolling near the end
        let actualContentLines = visibleLines.count

            // Calculate max line width from visible lines (trimmed)
            let maxLineWidth = visibleLines.reduce(0) { currentMax, line in
                let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let limited = min(cleaned.count, max(cols - 4, 0))
                return max(currentMax, limited)
            }

        let minDialogWidth = min(cols - 4, max(40, maxLineWidth + 4))
        let dialogWidth = max(10, minDialogWidth)
        // dialogHeight = top border (1) + content lines (actualContentLines) + bottom border (1)
        // Use actualContentLines to ensure correct alignment when showing fewer lines at scroll end
        let dialogHeight = actualContentLines + 2

        let startRow = max(0, (rows - dialogHeight) / 2)
        let startCol = max(0, (cols - dialogWidth) / 2)
        // endRow should be the last row of the dialog (bottom border)
        let endRow = min(rows - 1, startRow + dialogHeight - 1)
        // endCol is the last column of the dialog (inclusive) - so endCol = startCol + dialogWidth - 1
        let endCol = min(cols - 1, startCol + dialogWidth - 1)

        // Verify we have enough space and bounds are valid
        guard startRow >= 0 && endRow < rows && startCol >= 0 && endCol < cols && endRow >= startRow && endCol >= startCol && endRow >= 0 && startCol < cols && endCol >= startCol else {
            return frame
        }

        // Debug: verify dialog bounds
        assert(startRow >= 0 && startRow < rows, "startRow \(startRow) out of bounds [0, \(rows))")
        assert(endRow >= startRow && endRow < rows, "endRow \(endRow) out of bounds [\(startRow), \(rows))")
        assert(startCol >= 0 && startCol < cols, "startCol \(startCol) out of bounds [0, \(cols))")
        assert(endCol >= startCol && endCol < cols, "endCol \(endCol) out of bounds [\(startCol), \(cols))")

        var result: [String] = []
        result.reserveCapacity(rows)

        let paddedFrame: [String]
        if frame.count < rows {
            paddedFrame = frame + Array(repeating: String(repeating: " ", count: cols), count: rows - frame.count)
        } else if frame.count > rows {
            paddedFrame = Array(frame.prefix(rows))
        } else {
            paddedFrame = frame
        }

        for rowIndex in 0..<rows {
            var rowString: String
            if rowIndex < paddedFrame.count {
                let existing = paddedFrame[rowIndex]
                let stripped = ANSINormalizer.strip(existing)
                let visibleWidth = stripped.count
                if visibleWidth > cols {
                    let truncated = String(stripped.prefix(cols))
                    let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
                    var ansiCodes = ""
                    if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
                        let range = NSRange(existing.startIndex..<existing.endIndex, in: existing)
                        let ansiMatches = regex.matches(in: existing, options: [], range: range)
                        for match in ansiMatches {
                            if let matchRange = Range(match.range, in: existing) {
                                ansiCodes += String(existing[matchRange])
                            }
                        }
                    }
                    rowString = ansiCodes + truncated
                } else if visibleWidth < cols {
                    rowString = existing + String(repeating: " ", count: cols - visibleWidth)
                } else {
                    rowString = existing
                }
            } else {
                rowString = String(repeating: " ", count: cols)
            }

            if rowIndex >= startRow && rowIndex <= endRow {
                let stripped = ANSINormalizer.strip(rowString)
                let before = String(stripped.prefix(startCol))
                let afterStart = stripped.dropFirst(min(startCol + dialogWidth, stripped.count))
                let after = String(afterStart)

                rowString = before + String(repeating: " ", count: dialogWidth) + after

                if rowString.count != cols {
                    let paddingNeeded = cols - rowString.count
                    if paddingNeeded > 0 {
                        rowString = rowString + String(repeating: " ", count: paddingNeeded)
                    } else {
                        rowString = String(rowString.prefix(cols))
                    }
                }
            }

            result.append(rowString)
        }

        let horizontal = String(repeating: "═", count: max(dialogWidth - 2, 0))

        func write(row: Int, content: String) {
            guard row >= startRow && row <= endRow && row >= 0 && row < rows && row < result.count else { return }

            let strippedContent = ANSINormalizer.strip(content)
            var finalContent = strippedContent
            if strippedContent.count > dialogWidth {
                finalContent = String(strippedContent.prefix(dialogWidth))
            } else if strippedContent.count < dialogWidth {
                finalContent = strippedContent + String(repeating: " ", count: dialogWidth - strippedContent.count)
            }

            let existing = result[row]
            let existingStripped = ANSINormalizer.strip(existing)
            let before = String(existingStripped.prefix(startCol))
            let afterStart = existingStripped.dropFirst(min(startCol + dialogWidth, existingStripped.count))
            let after = String(afterStart)

            result[row] = before + finalContent + after

            if result[row].count != cols {
                let paddingNeeded = cols - result[row].count
                if paddingNeeded > 0 {
                    result[row] = result[row] + String(repeating: " ", count: paddingNeeded)
                } else {
                    result[row] = String(result[row].prefix(cols))
                }
            }
        }

        // Write top border
        // Format: ╔ + (dialogWidth - 2) × ═ + ╗ = dialogWidth characters total
        let topBorder = "╔\(horizontal)╗"
        // Verify it's the right length (should be dialogWidth)
        assert(topBorder.count == dialogWidth, "Top border should be \(dialogWidth) chars, got \(topBorder.count)")
        write(row: startRow, content: topBorder)

        // Write content lines - ensure we write the FULL dialog width including borders
        for (idx, line) in visibleLines.enumerated() {
            let contentRow = startRow + idx + 1
            guard contentRow > startRow && contentRow <= endRow else { continue }

            // Process help text line
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Calculate content width (dialog width minus border chars "║ " and " ║")
            let maxContentWidth = max(1, dialogWidth - 4)
            let contentToShow: String

            if trimmed.isEmpty {
                // Empty line - just spaces
                contentToShow = String(repeating: " ", count: maxContentWidth)
            } else {
                // Trim content to fit
                contentToShow = String(trimmed.prefix(maxContentWidth))
            }

            // Pad content to exact width, then write with borders
            // Format: "║ " + padded + " ║" = "║" (1) + " " (1) + padded (dialogWidth-4) + " " (1) + "║" (1) = dialogWidth
            // CRITICAL: maxContentWidth = dialogWidth - 4, so padded must be exactly maxContentWidth
            let exactPadded = contentToShow.padding(toLength: maxContentWidth, withPad: " ", startingAt: 0)
            let finalLine = "║ \(exactPadded) ║"

            // Verify line length matches dialogWidth exactly
            if finalLine.count != dialogWidth {
                // Force exact length by recalculating
                let recalcContent = String(trimmed.prefix(maxContentWidth))
                let recalcPadded = recalcContent.padding(toLength: maxContentWidth, withPad: " ", startingAt: 0)
                let correctedLine = "║ \(recalcPadded) ║"
                assert(correctedLine.count == dialogWidth, "Corrected line length \(correctedLine.count) != dialogWidth \(dialogWidth)")
                write(row: contentRow, content: correctedLine)
            } else {
                write(row: contentRow, content: finalLine)
            }
        }

        // Write bottom border (after all content lines)
        // Format: ╚ + (dialogWidth - 2) × ═ + ╝ = dialogWidth characters total
        // Use actualContentLines to calculate bottom border position correctly
        let bottomBorderRow = startRow + actualContentLines + 1
        if bottomBorderRow <= endRow && bottomBorderRow < rows {
            let bottomBorder = "╚\(horizontal)╝"
            // Verify it's the right length (should be dialogWidth)
            assert(bottomBorder.count == dialogWidth, "Bottom border should be \(dialogWidth) chars, got \(bottomBorder.count)")
            write(row: bottomBorderRow, content: bottomBorder)
        }

        return result
    }

    func renderFrameOnce(_ update: TUIUpdate?, prices: [String: Double]?, focus: PanelFocus?) async {
        guard !Task.isCancelled else { return }
        guard let update = update else { return }

        #if DEBUG
        let msg = "[renderFrameOnce] begin\n"
        msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
        defer {
            let endMsg = "[renderFrameOnce] end\n"
            endMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
        }
        #endif

        rendering = true
        defer { rendering = false }

        #if os(macOS) || os(Linux)
        let start = mach_continuous_time()
        defer {
            let dur = mach_continuous_time() - start
            let durMs = Double(dur) / 1_000_000.0
            if durMs > 12.0 {
                if TUIFeatureFlags.isDebugOverlayEnabled {
                    let msg = "[Render] Frame took \(durMs)ms (over 12ms budget)\n"
                    msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                }
            }
        }
        #endif

        let frame = await renderPanels(update, prices: prices, focus: focus)
        guard !Task.isCancelled else { return }

        await flushFrame(frame)
    }

    private func flushFrame(_ frame: [String]) async {
        guard !Task.isCancelled else { return }

        let isTTY = await Runtime.renderBus.isOutputTTY()
        guard isTTY else {
            guard !Task.isCancelled else { return }
            let frameContent = frame.joined(separator: "\n")
            await Runtime.renderBus.write(frameContent + "\n")
            return
        }

        if await Runtime.renderBus.hasTerminalResumed() {
            lastRenderedFrame = nil
        }

        guard !Task.isCancelled else { return }

        let finalFrame: [String]
        if let overlay = helpOverlayState {
            let terminalSize = cachedTerminalSize ?? detectAndCacheTerminalSize()
            finalFrame = applyHelpOverlay(to: frame, overlay: overlay, terminalSize: terminalSize)
            lastRenderedFrame = nil
        } else {
            finalFrame = frame
        }

        guard !Task.isCancelled else { return }

        let terminalSize = cachedTerminalSize ?? detectAndCacheTerminalSize()
        let maxLines = terminalSize.height
        let maxWidth = terminalSize.width

        let truncatedFrame = Array(finalFrame.prefix(maxLines).map { String($0.prefix(maxWidth)) })

        var fullOutput = ""
        let resetSequence = "\(esc)0m\(esc)?25h"

        if let previousFrame = lastRenderedFrame {
            let oldLines = previousFrame.count
            let newLines = truncatedFrame.count

            if oldLines != newLines || truncatedFrame != previousFrame {
                var firstChanged: Int? = nil
                var lastChanged: Int? = nil

                let minLines = min(oldLines, newLines)
                for i in 0..<minLines {
                    if previousFrame[i] != truncatedFrame[i] {
                        if firstChanged == nil {
                            firstChanged = i
                        }
                        lastChanged = i
                    }
                }

                if newLines > oldLines {
                    if firstChanged == nil {
                        firstChanged = oldLines
                    }
                    lastChanged = newLines - 1
                } else if newLines < oldLines {
                    if firstChanged == nil {
                        firstChanged = newLines
                    }
                    lastChanged = oldLines - 1
                }

                if let first = firstChanged, let last = lastChanged {
                    fullOutput += "\(esc)?25l"
                    fullOutput += "\(esc)\(first + 1);1H"

                    for i in first...min(last, newLines - 1) {
                        fullOutput += "\(esc)K\(truncatedFrame[i])"
                        if i < last && i < newLines - 1 {
                            fullOutput += "\r\n"
                        }
                    }

                    if last >= newLines {
                        for _ in newLines...last {
                            fullOutput += "\r\n\(esc)K"
                        }
                        fullOutput += "\(esc)\(last - newLines + 1)A"
                    }

                    fullOutput += resetSequence
                }
            }
        } else {
            let clearSequence = "\(esc)?25l\(esc)2J\(esc)H"
            fullOutput = clearSequence

            for (idx, line) in truncatedFrame.enumerated() {
                guard !Task.isCancelled else { return }
                fullOutput += "\(esc)K\(line)"
                if idx < truncatedFrame.count - 1 {
                    fullOutput += "\r\n"
                }
            }

            if truncatedFrame.count < maxLines {
                for _ in truncatedFrame.count..<maxLines {
                    guard !Task.isCancelled else { return }
                    fullOutput += "\r\n\(esc)K"
                }
            }

            fullOutput += resetSequence
        }

        guard !Task.isCancelled else { return }

        if !fullOutput.isEmpty {
            await coalescer.enqueue(fullOutput)
        }
        lastRenderedFrame = truncatedFrame
    }

    func getRendering() -> Bool {
        return rendering
    }

    public func getToggleManager() -> PanelToggleManager {
        return toggleManager
    }

    public func getScrollState() -> PanelScrollState {
        return scrollState
    }

    public func getPriceSortManager() -> PriceSortManager {
        return priceSortManager
    }

    public func getLogsRenderer() -> LogsPanelRenderer? {
        return logsRenderer
    }

    private func writeToGrid(_ grid: inout [[String]], lines: [String], at layout: PanelLayout) {
        let borderRenderer = PanelBorderRenderer(borderStyle: .unicode, unicodeSupported: colorManager.supportsUnicode)

        for (lineIdx, line) in lines.enumerated() {
            let gridY = layout.y + lineIdx
            guard gridY >= 0 && gridY < grid.count else { continue }
            guard gridY < layout.y + layout.height else { break }

            let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
            var strippedLine = line.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
            let tabWidth = 8
            strippedLine = strippedLine.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))
            let visibleWidth = borderRenderer.measureVisibleWidth(strippedLine)
            let targetWidth = layout.width

            var finalLine: String
            if visibleWidth != targetWidth {
                let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
                var ansiCodes = ""
                if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    let ansiMatches = regex.matches(in: line, options: [], range: range)
                    for match in ansiMatches {
                        if let matchRange = Range(match.range, in: line) {
                            ansiCodes += String(line[matchRange])
                        }
                    }
                }

                if visibleWidth > targetWidth {
                    var truncated = ""
                    var currentWidth = 0
                    var startIndex = strippedLine.startIndex
                    while startIndex < strippedLine.endIndex && currentWidth < targetWidth {
                        let graphemeRange = strippedLine.rangeOfComposedCharacterSequence(at: startIndex)
                        let grapheme = strippedLine[graphemeRange]
                        let graphemeWidth = borderRenderer.measureVisibleWidth(String(grapheme))
                        if currentWidth + graphemeWidth > targetWidth {
                            break
                        }
                        truncated += String(grapheme)
                        currentWidth += graphemeWidth
                        startIndex = graphemeRange.upperBound
                    }
                    finalLine = ansiCodes + truncated
                } else {
                    let paddingNeeded = targetWidth - visibleWidth
                    finalLine = ansiCodes + strippedLine + String(repeating: " ", count: paddingNeeded)
                }
            } else {
                finalLine = line
            }

            let verifiedStripped = finalLine.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
            let verifiedWidth = borderRenderer.measureVisibleWidth(verifiedStripped)

            #if DEBUG
            assert(verifiedWidth == targetWidth, "writeToGrid line \(lineIdx): visibleWidth \(verifiedWidth) != frame.width \(targetWidth)")
            #endif

            if verifiedWidth != targetWidth {
                let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
                var ansiCodes = ""
                if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
                    let range = NSRange(finalLine.startIndex..<finalLine.endIndex, in: finalLine)
                    let ansiMatches = regex.matches(in: finalLine, options: [], range: range)
                    for match in ansiMatches {
                        if let matchRange = Range(match.range, in: finalLine) {
                            ansiCodes += String(finalLine[matchRange])
                        }
                    }
                }

                if verifiedWidth > targetWidth {
                    var truncated = ""
                    var currentWidth = 0
                    var startIndex = verifiedStripped.startIndex
                    while startIndex < verifiedStripped.endIndex && currentWidth < targetWidth {
                        let graphemeRange = verifiedStripped.rangeOfComposedCharacterSequence(at: startIndex)
                        let grapheme = verifiedStripped[graphemeRange]
                        let graphemeWidth = borderRenderer.measureVisibleWidth(String(grapheme))
                        if currentWidth + graphemeWidth > targetWidth {
                            break
                        }
                        truncated += String(grapheme)
                        currentWidth += graphemeWidth
                        startIndex = graphemeRange.upperBound
                    }
                    finalLine = ansiCodes + truncated
                } else {
                    let paddingNeeded = targetWidth - verifiedWidth
                    finalLine = ansiCodes + verifiedStripped + String(repeating: " ", count: paddingNeeded)
                }

                let finalStripped = finalLine.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
                let finalWidth = borderRenderer.measureVisibleWidth(finalStripped)

                if TUIFeatureFlags.isDebugOverlayEnabled {
                    if finalWidth != targetWidth {
                        let msg = "[Grid ERROR] Line \(lineIdx) width mismatch: expected=\(targetWidth) got=\(finalWidth) panel=\(layout.x),\(layout.y) panelType=\(layout)\n"
                        msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                    } else if lineIdx < 3 || lineIdx % 10 == 0 {
                        let msg = "[Grid] Line \(lineIdx) width OK: \(finalWidth) panel=\(layout.x),\(layout.y)\n"
                        msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                    }
                }
            }

            var visibleIdx = 0
            var lineIdx = finalLine.startIndex
            let maxX = min(layout.x + targetWidth, grid[gridY].count)
            let minX = max(0, layout.x)
            var currentCell = ""
            var currentAnsi = ""

            while visibleIdx < targetWidth && lineIdx < finalLine.endIndex {
                let char = finalLine[lineIdx]

                if char == "\u{001B}" {
                    var ansiSeq = String(char)
                    lineIdx = finalLine.index(after: lineIdx)
                    while lineIdx < finalLine.endIndex {
                        let nextChar = finalLine[lineIdx]
                        ansiSeq.append(nextChar)
                        if nextChar >= "@" && nextChar <= "~" {
                            lineIdx = finalLine.index(after: lineIdx)
                            currentAnsi = ansiSeq
                            break
                        }
                        lineIdx = finalLine.index(after: lineIdx)
                    }
                } else {
                    let gridX = layout.x + visibleIdx
                    if gridX >= minX && gridX < maxX {
                        currentCell = currentAnsi + String(char)
                        grid[gridY][gridX] = currentCell
                        currentCell = ""
                        currentAnsi = ""
                    }
                    visibleIdx += 1
                    lineIdx = finalLine.index(after: lineIdx)
                }
            }

            while visibleIdx < targetWidth {
                let gridX = layout.x + visibleIdx
                if gridX >= minX && gridX < maxX && gridX < layout.x + targetWidth {
                    grid[gridY][gridX] = " "
                }
                visibleIdx += 1
            }
        }
    }

    public func showHelpOverlay(lines: [String], scrollOffset: Int) async {
        helpOverlayState = HelpOverlayState(lines: lines, scrollOffset: scrollOffset)
        await coalescer.flush()
    }

    public func hideHelpOverlay() async {
        helpOverlayState = nil
        lastRenderedFrame = nil
        await coalescer.flush()
    }

    public func isHelpOverlayVisible() async -> Bool {
        return helpOverlayState != nil
    }
}
