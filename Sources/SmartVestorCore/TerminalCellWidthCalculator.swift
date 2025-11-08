import Foundation

public final class TerminalCellWidthCalculator: @unchecked Sendable {
    private let terminalEnv: TerminalEnv

    public init(terminalEnv: TerminalEnv = TerminalEnv.detect()) {
        self.terminalEnv = terminalEnv
    }

    public func measureCellWidth(_ str: String) -> Int {
        let stripped = ANSINormalizer.strip(str)

        if stripped.isEmpty {
            return 0
        }

        let tabWidth = terminalEnv.tab
        let tabReplaced = stripped.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))

        if tabReplaced.utf8.allSatisfy({ $0 < 128 }) {
            return tabReplaced.count
        }

        return measureUnicodeWidth(tabReplaced)
    }

    private func measureUnicodeWidth(_ str: String) -> Int {
        var width = 0
        var index = str.startIndex

        while index < str.endIndex {
            let graphemeRange = str.rangeOfComposedCharacterSequence(at: index)
            let grapheme = str[graphemeRange]

            let graphemeWidth = try! TaskBlocking.runBlocking {
                await Text.widthCache.width(of: grapheme, env: self.terminalEnv)
            }
            width += graphemeWidth

            index = graphemeRange.upperBound
        }

        return width
    }

    private func calculateGraphemeWidth(_ grapheme: Substring) -> Int {
        let string = String(grapheme)

        if string.isEmpty {
            return 0
        }

        if string.utf8.allSatisfy({ $0 < 128 }) {
            return string.count
        }

        var width = 0
        for scalar in string.unicodeScalars {
            let codePoint = scalar.value

            if codePoint == 0 {
                continue
            }

            if (0x0001...0x001F).contains(codePoint) || (0x007F...0x009F).contains(codePoint) {
                continue
            }

            if (0x0300...0x036F).contains(codePoint) {
                continue
            }

            if (0x200B...0x200D).contains(codePoint) {
                continue
            }

            if (0xFE00...0xFE0F).contains(codePoint) {
                continue
            }

            if isBoxDrawingCharacter(codePoint) {
                width += 1
                continue
            }

            if terminalEnv.cjk {
                if isCJKCharacter(codePoint) {
                    width += 2
                    continue
                }
            }

            if isFullWidthCharacter(codePoint) {
                width += 2
                continue
            }

            width += 1
        }

        return width
    }

    private func isBoxDrawingCharacter(_ codePoint: UInt32) -> Bool {
        return (0x2500...0x257F).contains(codePoint)
    }

    private func isCJKCharacter(_ codePoint: UInt32) -> Bool {
        return (0x1100...0x115F).contains(codePoint) ||
               (0x2329...0x232A).contains(codePoint) ||
               (0x2E80...0x2FFF).contains(codePoint) ||
               (0x3000...0x303F).contains(codePoint) ||
               (0x3040...0x4DBF).contains(codePoint) ||
               (0x4E00...0x9FFF).contains(codePoint) ||
               (0xA000...0xA4CF).contains(codePoint) ||
               (0xAC00...0xD7A3).contains(codePoint) ||
               (0xF900...0xFAFF).contains(codePoint) ||
               (0xFE30...0xFE4F).contains(codePoint) ||
               (0xFE50...0xFE6F).contains(codePoint) ||
               (0xFF00...0xFFEF).contains(codePoint) ||
               (0x20000...0x2FFFD).contains(codePoint) ||
               (0x30000...0x3FFFD).contains(codePoint)
    }

    private func isFullWidthCharacter(_ codePoint: UInt32) -> Bool {
        return (0xFF01...0xFF60).contains(codePoint) ||
               (0xFFE0...0xFFE6).contains(codePoint) ||
               (0x3000...0x3000).contains(codePoint)
    }
}
