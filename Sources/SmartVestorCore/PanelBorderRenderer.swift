import Foundation
#if os(macOS) || os(Linux)
import Darwin
#endif

public struct PanelBorderRenderer: Sendable {
    private let borderStyle: BorderStyle
    private let unicodeSupported: Bool
    private let chars: BorderCharacters
    private let widthCalculator: TerminalCellWidthCalculator
    private nonisolated(unsafe) static var debugPrintCount: Int = 0
    private nonisolated(unsafe) static var lastDebugPrint: TimeInterval = 0
    private nonisolated(unsafe) static var debugPrintLock = NSLock()

    public init(borderStyle: BorderStyle, unicodeSupported: Bool, terminalEnv: TerminalEnv = TerminalEnv.detect()) {
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
        self.chars = borderStyle.characters(unicodeSupported: unicodeSupported)
        self.widthCalculator = TerminalCellWidthCalculator(terminalEnv: terminalEnv)
    }

    public func renderBorder(width: Int, height: Int, title: String? = nil, isFocused: Bool = false, colorManager: ColorManagerProtocol? = nil) -> [String] {
        guard borderStyle != .none else {
            return Array(repeating: String(repeating: " ", count: width), count: height)
        }

        var lines: [String] = []

        if let title = title, !title.isEmpty {
            let interior = width - 2

            let plainTitle: String
            let titleW = measureVisibleWidth(title)
            if titleW > interior - 2 {
                var truncated = ""
                var currentWidth = 0
                var startIndex = title.startIndex
                while startIndex < title.endIndex && currentWidth < interior - 5 {
                    let graphemeRange = title.rangeOfComposedCharacterSequence(at: startIndex)
                    let grapheme = title[graphemeRange]
                    let graphemeWidth = measureVisibleWidth(String(grapheme))
                    if currentWidth + graphemeWidth > interior - 5 {
                        break
                    }
                    truncated += String(grapheme)
                    currentWidth += graphemeWidth
                    startIndex = graphemeRange.upperBound
                }
                plainTitle = truncated + "..."
            } else {
                plainTitle = title
            }

            let plainTitleW = measureVisibleWidth(plainTitle)
            let leftPad = 1
            let rightPad = max(0, interior - leftPad - plainTitleW)

            let styledTitle: String
            let forceUnderlineTest = ProcessInfo.processInfo.environment["TUI_FORCE_UNDERLINE"] == "1"
            let shouldUnderline = isFocused || forceUnderlineTest

            if shouldUnderline {
                let esc = "\u{001B}["
                if colorManager != nil && colorManager!.supportsColor {
                    if let colorMgr = colorManager as? ColorManager {
                        styledTitle = colorMgr.applyColorAndStyle(.yellow, .underline, to: plainTitle)
                    } else {
                        styledTitle = "\(esc)4;33m\(plainTitle)\(esc)0m"
                    }
                } else {
                    styledTitle = "\(esc)4m\(plainTitle)\(esc)0m"
                }
            } else {
                styledTitle = plainTitle
            }

            var titleLine = String(chars.vertical) + String(repeating: " ", count: leftPad) + styledTitle + String(repeating: " ", count: rightPad) + String(chars.vertical)

            var verifiedWidth = measureVisibleWidth(titleLine)

            if verifiedWidth != width {
                #if DEBUG
                let msg = "[Border ERROR] Title line width mismatch: expected=\(width) got=\(verifiedWidth) title='\(plainTitle)' interior=\(interior) plainTitleW=\(plainTitleW) leftPad=\(leftPad) rightPad=\(rightPad)\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                #endif
                let borderWidth = measureVisibleWidth(String(chars.vertical))
                let totalBorderWidth = borderWidth * 2
                let correctedRightPad = max(0, width - totalBorderWidth - leftPad - plainTitleW)
                titleLine = String(chars.vertical) + String(repeating: " ", count: leftPad) + styledTitle + String(repeating: " ", count: correctedRightPad) + String(chars.vertical)
                verifiedWidth = measureVisibleWidth(titleLine)
                if verifiedWidth != width {
                    let finalRightPad = max(0, width - verifiedWidth + rightPad)
                    titleLine = String(chars.vertical) + String(repeating: " ", count: leftPad) + styledTitle + String(repeating: " ", count: finalRightPad) + String(chars.vertical)
                }
            }

            lines.append(titleLine)
        } else {
            let interior = width - 2
            let topBorder = chars.topLeft + String(repeating: chars.horizontal, count: interior) + chars.topRight

            let decoratedBorder = isFocused && colorManager != nil
                ? colorManager!.yellow(topBorder)
                : topBorder

            #if DEBUG
            let decoratedWidth = measureVisibleWidth(decoratedBorder)
            if decoratedWidth != width {
                let msg = "[Border ERROR] Top border width mismatch: expected=\(width) got=\(decoratedWidth)\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
            #endif

            lines.append(decoratedBorder)
        }

        let interior = width - 2
        let middleLine = String(chars.vertical) + String(repeating: " ", count: interior) + String(chars.vertical)

        #if DEBUG
        let finalMiddleWidth = measureVisibleWidth(middleLine)
        if finalMiddleWidth != width {
            let msg = "[Border ERROR] Middle line width mismatch: expected \(width), got \(finalMiddleWidth)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
        }
        #endif

        let finalMiddleLine = middleLine

        for _ in 0..<(height - 2) {
            lines.append(finalMiddleLine)
        }

        if height > 1 {
            let interior = width - 2
            let finalBottomBorder = chars.bottomLeft + String(repeating: chars.horizontal, count: interior) + chars.bottomRight

            #if DEBUG
            let finalBottomWidth = measureVisibleWidth(finalBottomBorder)
            if finalBottomWidth != width {
                let msg = "[Border ERROR] Bottom border width mismatch: expected=\(width) got=\(finalBottomWidth)\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
            #endif

            lines.append(finalBottomBorder)
        }

        #if DEBUG
        for (idx, line) in lines.enumerated() {
            let lineWidth = measureVisibleWidth(line)
            if lineWidth != width {
                let msg = "[Border ERROR] Line \(idx) width mismatch: expected \(width), got \(lineWidth)\n"
                msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
        }
        #endif

        return lines
    }

    public func renderTopBorder(width: Int) -> String {
        guard borderStyle != .none else {
            return String(repeating: " ", count: width)
        }
        let interior = width - 2
        return chars.topLeft + String(repeating: chars.horizontal, count: interior) + chars.topRight
    }

    public func renderBottomBorder(width: Int) -> String {
        guard borderStyle != .none else {
            return String(repeating: " ", count: width)
        }
        let interior = width - 2
        return chars.bottomLeft + String(repeating: chars.horizontal, count: interior) + chars.bottomRight
    }

    public func measureVisibleWidth(_ str: String) -> Int {
        return widthCalculator.measureCellWidth(str)
    }

    public func renderContentLine(content: String, width: Int, padding: Int = 1) -> String {
        guard borderStyle != .none else {
            return content.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        let paddingStr = String(repeating: " ", count: padding)
        let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        let strippedContent = ANSINormalizer.strip(content)

        let leftPart = chars.vertical + paddingStr
        let rightPart = paddingStr + chars.vertical
        let leftPartWidth = measureVisibleWidth(leftPart)
        let rightPartWidth = measureVisibleWidth(rightPart)
        let contentAreaWidth = width - leftPartWidth - rightPartWidth

        let displayContent: String
        let visibleContentWidth = measureVisibleWidth(strippedContent)
        if visibleContentWidth > contentAreaWidth {
            var truncated = ""
            var currentWidth = 0
            var startIndex = strippedContent.startIndex
            while startIndex < strippedContent.endIndex && currentWidth < contentAreaWidth {
                let graphemeRange = strippedContent.rangeOfComposedCharacterSequence(at: startIndex)
                let grapheme = strippedContent[graphemeRange]
                let graphemeWidth = measureVisibleWidth(String(grapheme))
                if currentWidth + graphemeWidth > contentAreaWidth {
                    break
                }
                truncated += String(grapheme)
                currentWidth += graphemeWidth
                startIndex = graphemeRange.upperBound
            }

            if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                let ansiMatches = regex.matches(in: content, options: [], range: range)
                var codes = ""
                for match in ansiMatches {
                    if let matchRange = Range(match.range, in: content) {
                        codes += String(content[matchRange])
                    }
                }
                displayContent = codes + truncated
            } else {
                displayContent = truncated
            }
        } else {
            displayContent = content
        }

        let displayContentStripped = ANSINormalizer.strip(displayContent)
        let visibleWidth = measureVisibleWidth(displayContentStripped)
        let totalWidth = leftPartWidth + visibleWidth + rightPartWidth
        let paddingNeeded = max(0, width - totalWidth)

        var ansiCodes = ""
        if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
            let range = NSRange(displayContent.startIndex..<displayContent.endIndex, in: displayContent)
            let ansiMatches = regex.matches(in: displayContent, options: [], range: range)
            for match in ansiMatches {
                if let matchRange = Range(match.range, in: displayContent) {
                    ansiCodes += String(displayContent[matchRange])
                }
            }
        }

        var result = leftPart
        result += ansiCodes
        result += displayContentStripped
        if paddingNeeded > 0 {
            result += String(repeating: " ", count: paddingNeeded)
        }
        result += rightPart

        let verifiedWidth = measureVisibleWidth(result)

        #if DEBUG
        if TUIFeatureFlags.isDebugOverlayEnabled {
            if verifiedWidth != width {
                let errorMsg = "[Border ERROR] Line width mismatch: expected=\(width) got=\(verifiedWidth) content='\(displayContentStripped.prefix(20))'\n"
                errorMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
        }
        if verifiedWidth != width {
            let errorMsg = "[Border ERROR] renderContentLine width mismatch: expected=\(width) got=\(verifiedWidth)\n"
            errorMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
        }
        #endif

        if verifiedWidth != width {
            let exactPadding = max(0, width - leftPartWidth - visibleWidth - rightPartWidth)
            return leftPart + ansiCodes + displayContentStripped + String(repeating: " ", count: exactPadding) + rightPart
        }

        return result
    }

    public func wrapContent(content: [String], width: Int, padding: Int = 1) -> [String] {
        var result: [String] = []

        for line in content {
            result.append(renderContentLine(content: line, width: width, padding: padding))
        }

        return result
    }
}
