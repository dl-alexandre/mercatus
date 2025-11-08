import Foundation

public protocol GraphScaler: Sendable {
    func scale(_ values: [Double]) -> [Double]
}

public struct FixedScaler: GraphScaler {
    public let min: Double
    public let max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    public func scale(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }

        let range = self.max - self.min
        guard range > 0 else {
            return Array(repeating: self.min, count: values.count)
        }

        return values.map { value in
            let normalized = (value - self.min) / range
            return Swift.max(0.0, Swift.min(1.0, normalized))
        }
    }
}

public struct AutoScaler: GraphScaler {
    public init() {}

    public func scale(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }

        guard let dataMin = values.min(), let dataMax = values.max() else {
            return Array(repeating: 0.0, count: values.count)
        }

        if dataMax == dataMin {
            return Array(repeating: 1.0, count: values.count)
        }

        let range = dataMax - dataMin
        return values.map { ($0 - dataMin) / range }
    }
}

public struct SyncScaler: GraphScaler {
    public let sharedRange: ClosedRange<Double>

    public init(sharedRange: ClosedRange<Double>) {
        self.sharedRange = sharedRange
    }

    public func scale(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }

        let rangeMin = sharedRange.lowerBound
        let rangeMax = sharedRange.upperBound
        let range = rangeMax - rangeMin

        guard range > 0 else {
            return Array(repeating: 0.0, count: values.count)
        }

        return values.map { value in
            let normalized = (value - rangeMin) / range
            return Swift.max(0.0, Swift.min(1.0, normalized))
        }
    }
}
