import Foundation

public final class SparklineRenderer: @unchecked Sendable {
    private let unicodeSupported: Bool
    private let graphMode: GraphMode
    private let scaler: GraphScaler

    public init(
        unicodeSupported: Bool = true,
        graphMode: GraphMode = .default,
        scaler: GraphScaler = AutoScaler()
    ) {
        self.unicodeSupported = unicodeSupported
        self.graphMode = graphMode
        self.scaler = scaler
    }

    public func render(
        values: [Double],
        width: Int,
        minHeight: Int = 1,
        maxHeight: Int = 4
    ) -> String {
        let startTime = ContinuousClock.now

        guard width > 0 && !values.isEmpty else {
            return ""
        }

        let symbolSet = selectSymbolSet()
        let characters = symbolSet.characters
        let heightLevels = maxHeight - minHeight + 1

        Task {
            await TUIMetrics.shared.recordGraphModeSelection(graphMode.rawValue)
        }

        let normalized = scaler.scale(values)
        let sampled = sampleValues(normalized, targetWidth: width)

        var result = ""

        for value in sampled {
            let level = mapToLevel(value, minHeight: minHeight, maxHeight: maxHeight, heightLevels: heightLevels)
            let charIndex = min(level - minHeight, characters.count - 1)
            result.append(characters[charIndex])
        }

        let endTime = ContinuousClock.now
        let renderTime = startTime.duration(to: endTime).timeInterval * 1000.0

        Task {
            await TUIMetrics.shared.recordGraphRenderTime(renderTime)
        }

        return result
    }

    private func selectSymbolSet() -> GraphSymbolSet {
        let fallbackOrder = graphMode.fallbackOrder

        for mode in fallbackOrder {
            let symbolSet = mode.symbolSet
            if mode == .braille || mode == .block || mode == .default {
                if unicodeSupported {
                    return symbolSet
                }
            } else if mode == .tty || mode == .ascii {
                return symbolSet
            }
        }

        return GraphSymbolSet.ascii
    }

    private func sampleValues(_ values: [Double], targetWidth: Int) -> [Double] {
        guard targetWidth > 0 && !values.isEmpty else {
            return []
        }

        if values.count == targetWidth {
            return values
        }

        if values.count == 1 {
            return Array(repeating: values[0], count: targetWidth)
        }

        if values.count < targetWidth {
            var sampled: [Double] = []

            for i in 0..<targetWidth {
                let position = Double(i) * Double(values.count - 1) / Double(targetWidth - 1)
                let lowerIndex = Int(floor(position))
                let upperIndex = min(Int(ceil(position)), values.count - 1)

                if lowerIndex == upperIndex {
                    sampled.append(values[lowerIndex])
                } else {
                    let t = position - Double(lowerIndex)
                    let interpolated = values[lowerIndex] * (1.0 - t) + values[upperIndex] * t
                    sampled.append(interpolated)
                }
            }

            return sampled
        }

        var sampled: [Double] = []
        let step = Double(values.count) / Double(targetWidth)

        for i in 0..<targetWidth {
            let startIndex = Int(Double(i) * step)
            let endIndex = min(Int(Double(i + 1) * step), values.count)

            let segment = values[startIndex..<endIndex]
            let average = segment.reduce(0.0, +) / Double(segment.count)
            sampled.append(average)
        }

        return sampled
    }

    private func mapToLevel(_ normalizedValue: Double, minHeight: Int, maxHeight: Int, heightLevels: Int) -> Int {
        let clamped = max(0.0, min(1.0, normalizedValue))
        let level = Int(round(clamped * Double(heightLevels - 1))) + minHeight
        return max(minHeight, min(maxHeight, level))
    }
}
