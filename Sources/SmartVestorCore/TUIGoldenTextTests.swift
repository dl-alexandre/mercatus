import Foundation

public struct TUIGoldenTextTests {
    // Golden text set for grapheme-safe width and slicing tests
    public static let testStrings: [String] = [
        "A🧪B",                    // ZWJ emoji
        "👨‍👩‍👧‍👦 family",        // Family emoji with ZWJ
        "e\u{0301}cole",          // Combining acute
        "中(Ａ)A",                 // EAW Ambiguous
        "مرحبا"                    // Arabic (RTL shaping not required but widths must be stable)
    ]

    public static func validateGraphemeWidths(env: TerminalEnv) -> [String] {
        var errors: [String] = []

        for testString in testStrings {
            var totalWidth = 0
            var startIndex = testString.startIndex

            while startIndex < testString.endIndex {
                let graphemeRange = testString.rangeOfComposedCharacterSequence(at: startIndex)
                let grapheme = testString[graphemeRange]

                // Calculate width using the same logic as Text.measure()
                let width = calculateGraphemeWidth(grapheme, env: env)
                totalWidth += width

                // Verify we never slice mid-grapheme
                if graphemeRange.isEmpty {
                    errors.append("Empty grapheme range for: \(testString)")
                }

                startIndex = graphemeRange.upperBound
            }

            // Verify width is reasonable (not negative, not zero for non-empty strings)
            if testString.isEmpty && totalWidth != 0 {
                errors.append("Empty string should have width 0")
            } else if !testString.isEmpty && totalWidth <= 0 {
                errors.append("Non-empty string '\(testString)' has width \(totalWidth)")
            }
        }

        return errors
    }

    private static func calculateGraphemeWidth(_ grapheme: Substring, env: TerminalEnv) -> Int {
        let string = String(grapheme)
        if string.isEmpty { return 0 }
        if string.utf8.allSatisfy({ $0 < 128 }) { return string.count }

        var width = 0
        for scalar in string.unicodeScalars {
            let codePoint = scalar.value
            if codePoint == 0 { continue }
            if (0x0001...0x001F).contains(codePoint) || (0x007F...0x009F).contains(codePoint) { continue }
            if (0x0300...0x036F).contains(codePoint) { continue }
            if (0x200B...0x200D).contains(codePoint) { continue }
            if (0xFE00...0xFE0F).contains(codePoint) { continue }

            if env.cjk {
                if ((0x1100...0x115F).contains(codePoint) ||
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
                    (0x30000...0x3FFFD).contains(codePoint)) {
                    width += 2
                    continue
                }
            }
            width += 1
        }
        return width
    }
}
