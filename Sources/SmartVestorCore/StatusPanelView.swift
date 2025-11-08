import Foundation

public struct StatusPanelView: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let update: TUIUpdate
    private let layout: PanelLayout
    private let colorManager: ColorManagerProtocol
    private let borderStyle: BorderStyle
    private let unicodeSupported: Bool
    private let isFocused: Bool
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = [.state]
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { true }

    public init(
        update: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool = false,
        id: AnyHashable? = nil
    ) {
        self.update = update
        self.layout = layout
        self.colorManager = colorManager
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
        self.isFocused = isFocused
        self.id = id ?? AnyHashable(PanelType.status.rawValue)
        self.nodeID = NodeID()
        self._dirtyReasons = [.state]
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached == size {
            return cached
        }
        let effectiveHeight = max(6, layout.height)
        return Size(width: layout.width, height: effectiveHeight)
    }

    public mutating func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
        _measuredSize = nil
    }

    public mutating func clearDirty() {
        _dirtyReasons = []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(id)
        hasher.combine(layout.width)
        hasher.combine(layout.height)
        hasher.combine(isFocused)
    }

    public mutating func markDirty() {
        markDirty(.state)
    }

    public func onFocusChange(_ focused: Bool) {
        if TUIFeatureFlags.isDebugTreeEnabled {
            let msg = "[Focus] StatusPanelView.onFocusChange(\(focused))\n"
            #if os(macOS) || os(Linux)
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            #else
            print(msg, to: &FileHandle.standardError)
            #endif
        }
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let effectiveHeight = max(6, layout.height)

        let state = update.state
        let data = update.data

        let isRunning = state.isRunning
        let hasErrors = data.errorCount > 0
        let circuitBreakerOpen = data.circuitBreakerOpen

        let statusText: String
        if !isRunning {
            statusText = colorManager.red("STOPPED")
        } else if hasErrors || circuitBreakerOpen {
            statusText = colorManager.yellow("WARNING")
        } else {
            statusText = colorManager.green("RUNNING")
        }

        let borderLines = borderRenderer.renderBorder(
            width: width,
            height: effectiveHeight,
            title: "Status",
            isFocused: isFocused,
            colorManager: colorManager
        )

        guard borderLines.count >= 2 else {
            return
        }

        var currentY = origin.y

        if currentY < buf.size.height {
            buf.write(borderLines[0], at: Point(x: origin.x, y: currentY))
        }
        currentY += 1

        let formatter = ISO8601DateFormatter()

        let contentLines: [(String, String)] = [
            ("State", statusText),
            ("Mode", colorManager.blue(state.mode.rawValue)),
            ("Sequence", colorManager.dim(String(update.sequenceNumber))),
            ("Timestamp", colorManager.dim(formatter.string(from: update.timestamp)))
        ]

        for (label, value) in contentLines {
            if currentY >= origin.y + effectiveHeight - 1 {
                break
            }
            let line = "\(label): \(value)"
            if currentY < buf.size.height {
                let rendered = borderRenderer.renderContentLine(content: line, width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1
        }

        if hasErrors || circuitBreakerOpen {
            if currentY < origin.y + effectiveHeight - 1 && currentY < buf.size.height {
                var errorParts: [String] = []
                if data.errorCount > 0 {
                    errorParts.append("\(data.errorCount) error\(data.errorCount == 1 ? "" : "s")")
                }
                if circuitBreakerOpen {
                    errorParts.append("Circuit Breaker: \(colorManager.red("OPEN"))")
                } else {
                    errorParts.append("Circuit Breaker: \(colorManager.green("CLOSED"))")
                }

                let errorLine = "Errors: \(errorParts.joined(separator: ", "))"
                let rendered = borderRenderer.renderContentLine(content: errorLine, width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
                currentY += 1
            }
        } else {
            if currentY < origin.y + effectiveHeight - 1 && currentY < buf.size.height {
                let cbLine = "Circuit Breaker: \(colorManager.green("CLOSED"))"
                let rendered = borderRenderer.renderContentLine(content: cbLine, width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
                currentY += 1
            }
        }

        if let lastExec = data.lastExecutionTime {
            if currentY < origin.y + effectiveHeight - 1 && currentY < buf.size.height {
                let lastExecStr = formatter.string(from: lastExec)
                let lastExecLine = "Last Exec: \(colorManager.dim(lastExecStr))"
                let rendered = borderRenderer.renderContentLine(content: lastExecLine, width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
                currentY += 1
            }
        }

        while currentY < origin.y + effectiveHeight - 1 {
            if currentY < buf.size.height {
                let rendered = borderRenderer.renderContentLine(content: "", width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1
        }

        if effectiveHeight > 1 && borderLines.count > 1 && currentY < buf.size.height {
            buf.write(borderLines[borderLines.count - 1], at: Point(x: origin.x, y: currentY))
        }
    }

    public func children() -> [TUIRenderable] {
        return []
    }
}
