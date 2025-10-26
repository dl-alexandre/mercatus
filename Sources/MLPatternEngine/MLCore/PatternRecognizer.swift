import Foundation
import Utils

public class PatternRecognizer: PatternRecognitionProtocol {
    private let logger: StructuredLogger
    private let patternStorage: PatternStorageProtocol?

    public init(logger: StructuredLogger, patternStorage: PatternStorageProtocol? = nil) {
        self.logger = logger
        self.patternStorage = patternStorage
    }

    public func detectPatterns(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        guard dataPoints.count >= 50 else {
            throw PatternDetectionError.insufficientData
        }

        var allPatterns: [DetectedPattern] = []

        for patternType in DetectedPattern.PatternType.allCases {
            do {
                let patterns = try await detectPattern(in: dataPoints, patternType: patternType)
                allPatterns.append(contentsOf: patterns)
            } catch {
                logger.warn(component: "PatternRecognizer", event: "Failed to detect \(patternType.rawValue) patterns: \(error)")
            }
        }

        let sortedPatterns = allPatterns.sorted { $0.confidence > $1.confidence }

        // Store patterns in database if storage is available
        if let patternStorage = patternStorage {
            do {
                try await patternStorage.storePatterns(sortedPatterns)
                logger.debug(component: "PatternRecognizer", event: "Stored \(sortedPatterns.count) patterns in database")
            } catch {
                logger.warn(component: "PatternRecognizer", event: "Failed to store patterns: \(error)")
            }
        }

        return sortedPatterns
    }

    // MARK: - Pattern Storage Methods

    public func getStoredPatterns(
        symbol: String? = nil,
        patternType: DetectedPattern.PatternType? = nil,
        from: Date? = nil,
        to: Date? = nil,
        minConfidence: Double? = nil
    ) async throws -> [DetectedPattern] {
        guard let patternStorage = patternStorage else {
            throw PatternDetectionError.storageNotAvailable
        }

        return try await patternStorage.getPatterns(
            symbol: symbol,
            patternType: patternType,
            from: from,
            to: to,
            minConfidence: minConfidence
        )
    }

    public func getHighConfidencePatterns(minConfidence: Double = 0.8, limit: Int? = nil) async throws -> [DetectedPattern] {
        guard let patternStorage = patternStorage else {
            throw PatternDetectionError.storageNotAvailable
        }

        return try await patternStorage.getPatternsByConfidence(minConfidence: minConfidence, limit: limit)
    }

    public func getPatternsByType(_ patternType: DetectedPattern.PatternType, limit: Int? = nil) async throws -> [DetectedPattern] {
        guard let patternStorage = patternStorage else {
            throw PatternDetectionError.storageNotAvailable
        }

        return try await patternStorage.getPatternsByType(patternType, limit: limit)
    }

    public func getPatternCount(symbol: String? = nil, patternType: DetectedPattern.PatternType? = nil) async throws -> Int {
        guard let patternStorage = patternStorage else {
            throw PatternDetectionError.storageNotAvailable
        }

        return try await patternStorage.getPatternCount(symbol: symbol, patternType: patternType)
    }

    public func cleanupOldPatterns(olderThan: Date) async throws {
        guard let patternStorage = patternStorage else {
            throw PatternDetectionError.storageNotAvailable
        }

        try await patternStorage.deleteOldPatterns(olderThan: olderThan)
    }

    public func detectPattern(in dataPoints: [MarketDataPoint], patternType: DetectedPattern.PatternType) async throws -> [DetectedPattern] {
        switch patternType {
        case .headAndShoulders:
            return try await detectHeadAndShoulders(in: dataPoints)
        case .triangle:
            return try await detectTriangles(in: dataPoints)
        case .flag:
            return try await detectFlags(in: dataPoints)
        case .supportResistance:
            return try await detectSupportResistance(in: dataPoints)
        case .trendChannel:
            return try await detectTrendChannels(in: dataPoints)
        case .doubleTop:
            return try await detectDoubleTops(in: dataPoints)
        case .doubleBottom:
            return try await detectDoubleBottoms(in: dataPoints)
        }
    }

    public func calculatePatternConfidence(_ pattern: DetectedPattern, historicalData: [MarketDataPoint]) -> Double {
        let patternDuration = pattern.endTime.timeIntervalSince(pattern.startTime)
        let minDuration: TimeInterval = 3600 // 1 hour
        let maxDuration: TimeInterval = 7 * 24 * 3600 // 7 days

        var confidence = pattern.completionScore

        if patternDuration < minDuration || patternDuration > maxDuration {
            confidence *= 0.5
        }

        let priceMovement = calculatePriceMovement(for: pattern, in: historicalData)
        if priceMovement > 0.1 {
            confidence *= 1.2
        } else if priceMovement < 0.02 {
            confidence *= 0.8
        }

        return min(1.0, max(0.0, confidence))
    }

    public func validatePattern(_ pattern: DetectedPattern) -> Bool {
        return pattern.confidence > 0.3 &&
               pattern.completionScore > 0.5 &&
               pattern.startTime < pattern.endTime
    }

    private func detectHeadAndShoulders(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 20..<(prices.count - 20) {
            let window = Array(prices[(i-20)...(i+20)])
            let peaks = findPeaks(in: window)

            if peaks.count >= 3 {
                let leftShoulder = peaks[0]
                let head = peaks[1]
                let rightShoulder = peaks[2]

                if head > leftShoulder && head > rightShoulder &&
                   abs(leftShoulder - rightShoulder) / leftShoulder < 0.05 {

                    let completionScore = calculateHeadAndShouldersCompletion(
                        leftShoulder: leftShoulder,
                        head: head,
                        rightShoulder: rightShoulder
                    )

                    if completionScore > 0.6 {
                        let pattern = DetectedPattern(
                            patternId: UUID().uuidString,
                            patternType: .headAndShoulders,
                            symbol: dataPoints[i].symbol,
                            startTime: dataPoints[i-20].timestamp,
                            endTime: dataPoints[i+20].timestamp,
                            confidence: completionScore,
                            completionScore: completionScore,
                            priceTarget: calculatePriceTarget(for: .headAndShoulders, head: head, shoulders: [leftShoulder, rightShoulder]),
                            stopLoss: head * 1.02
                        )
                        patterns.append(pattern)
                    }
                }
            }
        }

        return patterns
    }

    private func detectTriangles(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 30..<(prices.count - 10) {
            let window = Array(prices[(i-30)...(i+10)])
            let highs = dataPoints[(i-30)...(i+10)].map { $0.high }
            let lows = dataPoints[(i-30)...(i+10)].map { $0.low }

            let upperTrend = calculateTrendLine(highs)
            let lowerTrend = calculateTrendLine(lows)

            if abs(upperTrend.slope) > 0.001 && abs(lowerTrend.slope) > 0.001 {
                let convergence = calculateConvergence(upperTrend, lowerTrend)

                if convergence > 0.7 {
                    let completionScore = calculateTriangleCompletion(window, upperTrend, lowerTrend)

                    if completionScore > 0.6 {
                        let pattern = DetectedPattern(
                            patternId: UUID().uuidString,
                            patternType: .triangle,
                            symbol: dataPoints[i].symbol,
                            startTime: dataPoints[i-30].timestamp,
                            endTime: dataPoints[i+10].timestamp,
                            confidence: completionScore,
                            completionScore: completionScore
                        )
                        patterns.append(pattern)
                    }
                }
            }
        }

        return patterns
    }

    private func detectFlags(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 20..<(prices.count - 10) {
            let flagPole = Array(prices[(i-20)...(i-5)])
            let flag = Array(prices[(i-5)...(i+5)])

            let poleTrend = calculateTrendLine(flagPole)
            let flagTrend = calculateTrendLine(flag)

            if abs(poleTrend.slope) > 0.01 && abs(flagTrend.slope) < 0.005 {
                let completionScore = calculateFlagCompletion(flagPole, flag)

                if completionScore > 0.7 {
                    let pattern = DetectedPattern(
                        patternId: UUID().uuidString,
                        patternType: .flag,
                        symbol: dataPoints[i].symbol,
                        startTime: dataPoints[i-20].timestamp,
                        endTime: dataPoints[i+5].timestamp,
                        confidence: completionScore,
                        completionScore: completionScore
                    )
                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    private func detectSupportResistance(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let _ = dataPoints.map { $0.close }
        let highs = dataPoints.map { $0.high }
        let lows = dataPoints.map { $0.low }

        let supportLevels = findSupportLevels(lows)
        let resistanceLevels = findResistanceLevels(highs)

        for level in supportLevels {
            let pattern = DetectedPattern(
                patternId: UUID().uuidString,
                patternType: .supportResistance,
                symbol: dataPoints.first?.symbol ?? "",
                startTime: dataPoints.first?.timestamp ?? Date(),
                endTime: dataPoints.last?.timestamp ?? Date(),
                confidence: level.strength,
                completionScore: level.strength,
                priceTarget: level.price * 1.05
            )
            patterns.append(pattern)
        }

        for level in resistanceLevels {
            let pattern = DetectedPattern(
                patternId: UUID().uuidString,
                patternType: .supportResistance,
                symbol: dataPoints.first?.symbol ?? "",
                startTime: dataPoints.first?.timestamp ?? Date(),
                endTime: dataPoints.last?.timestamp ?? Date(),
                confidence: level.strength,
                completionScore: level.strength,
                priceTarget: level.price * 0.95
            )
            patterns.append(pattern)
        }

        return patterns
    }

    private func detectTrendChannels(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 50..<(prices.count - 10) {
            let window = Array(prices[(i-50)...(i+10)])
            let highs = dataPoints[(i-50)...(i+10)].map { $0.high }
            let lows = dataPoints[(i-50)...(i+10)].map { $0.low }

            let upperChannel = calculateTrendLine(highs)
            let lowerChannel = calculateTrendLine(lows)

            if abs(upperChannel.slope - lowerChannel.slope) < 0.001 {
                let channelWidth = calculateChannelWidth(upperChannel, lowerChannel, window.count)
                let completionScore = calculateChannelCompletion(window, upperChannel, lowerChannel)

                if completionScore > 0.6 && channelWidth > 0.02 {
                    let pattern = DetectedPattern(
                        patternId: UUID().uuidString,
                        patternType: .trendChannel,
                        symbol: dataPoints[i].symbol,
                        startTime: dataPoints[i-50].timestamp,
                        endTime: dataPoints[i+10].timestamp,
                        confidence: completionScore,
                        completionScore: completionScore
                    )
                    patterns.append(pattern)
                }
            }
        }

        return patterns
    }

    private func detectDoubleTops(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 20..<(prices.count - 20) {
            let window = Array(prices[(i-20)...(i+20)])
            let peaks = findPeaks(in: window)

            if peaks.count >= 2 {
                let firstPeak = peaks[0]
                let secondPeak = peaks[1]

                if abs(firstPeak - secondPeak) / firstPeak < 0.03 {
                    let completionScore = calculateDoubleTopCompletion(firstPeak, secondPeak, window)

                    if completionScore > 0.7 {
                        let pattern = DetectedPattern(
                            patternId: UUID().uuidString,
                            patternType: .doubleTop,
                            symbol: dataPoints[i].symbol,
                            startTime: dataPoints[i-20].timestamp,
                            endTime: dataPoints[i+20].timestamp,
                            confidence: completionScore,
                            completionScore: completionScore,
                            priceTarget: (firstPeak + secondPeak) / 2 * 0.95
                        )
                        patterns.append(pattern)
                    }
                }
            }
        }

        return patterns
    }

    private func detectDoubleBottoms(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let prices = dataPoints.map { $0.close }

        for i in 20..<(prices.count - 20) {
            let window = Array(prices[(i-20)...(i+20)])
            let troughs = findTroughs(in: window)

            if troughs.count >= 2 {
                let firstTrough = troughs[0]
                let secondTrough = troughs[1]

                if abs(firstTrough - secondTrough) / firstTrough < 0.03 {
                    let completionScore = calculateDoubleBottomCompletion(firstTrough, secondTrough, window)

                    if completionScore > 0.7 {
                        let pattern = DetectedPattern(
                            patternId: UUID().uuidString,
                            patternType: .doubleBottom,
                            symbol: dataPoints[i].symbol,
                            startTime: dataPoints[i-20].timestamp,
                            endTime: dataPoints[i+20].timestamp,
                            confidence: completionScore,
                            completionScore: completionScore,
                            priceTarget: (firstTrough + secondTrough) / 2 * 1.05
                        )
                        patterns.append(pattern)
                    }
                }
            }
        }

        return patterns
    }

    private func findPeaks(in prices: [Double]) -> [Double] {
        var peaks: [Double] = []

        for i in 1..<(prices.count - 1) {
            if prices[i] > prices[i-1] && prices[i] > prices[i+1] {
                peaks.append(prices[i])
            }
        }

        return peaks
    }

    private func findTroughs(in prices: [Double]) -> [Double] {
        var troughs: [Double] = []

        for i in 1..<(prices.count - 1) {
            if prices[i] < prices[i-1] && prices[i] < prices[i+1] {
                troughs.append(prices[i])
            }
        }

        return troughs
    }

    private func calculateTrendLine(_ values: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(values.count)
        let x = Array(0..<values.count).map { Double($0) }

        let sumX = x.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(x, values).map(*).reduce(0, +)
        let sumXX = x.map { $0 * $0 }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n

        return (slope, intercept)
    }

    private func calculateConvergence(_ line1: (slope: Double, intercept: Double), _ line2: (slope: Double, intercept: Double)) -> Double {
        let slopeDiff = abs(line1.slope - line2.slope)
        let interceptDiff = abs(line1.intercept - line2.intercept)

        return 1.0 / (1.0 + slopeDiff + interceptDiff)
    }

    private func calculatePriceMovement(for pattern: DetectedPattern, in dataPoints: [MarketDataPoint]) -> Double {
        let relevantData = dataPoints.filter {
            $0.timestamp >= pattern.startTime && $0.timestamp <= pattern.endTime
        }

        guard let firstPrice = relevantData.first?.close,
              let lastPrice = relevantData.last?.close else {
            return 0.0
        }

        return abs(lastPrice - firstPrice) / firstPrice
    }

    private func calculatePriceTarget(for patternType: DetectedPattern.PatternType, head: Double, shoulders: [Double]) -> Double {
        switch patternType {
        case .headAndShoulders:
            let neckline = shoulders.reduce(0, +) / Double(shoulders.count)
            return neckline - (head - neckline)
        default:
            return head
        }
    }

    private func calculateHeadAndShouldersCompletion(leftShoulder: Double, head: Double, rightShoulder: Double) -> Double {
        let shoulderSymmetry = 1.0 - abs(leftShoulder - rightShoulder) / max(leftShoulder, rightShoulder)
        let headProminence = (head - max(leftShoulder, rightShoulder)) / head
        return (shoulderSymmetry + headProminence) / 2.0
    }

    private func calculateTriangleCompletion(_ prices: [Double], _ upperTrend: (slope: Double, intercept: Double), _ lowerTrend: (slope: Double, intercept: Double)) -> Double {
        let convergence = calculateConvergence(upperTrend, lowerTrend)
        let priceFit = calculatePriceFit(prices, upperTrend, lowerTrend)
        return (convergence + priceFit) / 2.0
    }

    private func calculateFlagCompletion(_ flagPole: [Double], _ flag: [Double]) -> Double {
        let poleTrend = calculateTrendLine(flagPole)
        let flagTrend = calculateTrendLine(flag)

        let poleStrength = abs(poleTrend.slope)
        let flagWeakness = 1.0 - abs(flagTrend.slope)

        return (poleStrength + flagWeakness) / 2.0
    }

    private func calculateChannelCompletion(_ prices: [Double], _ upperChannel: (slope: Double, intercept: Double), _ lowerChannel: (slope: Double, intercept: Double)) -> Double {
        let priceFit = calculatePriceFit(prices, upperChannel, lowerChannel)
        let channelConsistency = 1.0 - abs(upperChannel.slope - lowerChannel.slope)
        return (priceFit + channelConsistency) / 2.0
    }

    private func calculateDoubleTopCompletion(_ firstPeak: Double, _ secondPeak: Double, _ prices: [Double]) -> Double {
        let peakSimilarity = 1.0 - abs(firstPeak - secondPeak) / max(firstPeak, secondPeak)
        let valleyDepth = calculateValleyDepth(prices)
        return (peakSimilarity + valleyDepth) / 2.0
    }

    private func calculateDoubleBottomCompletion(_ firstTrough: Double, _ secondTrough: Double, _ prices: [Double]) -> Double {
        let troughSimilarity = 1.0 - abs(firstTrough - secondTrough) / max(firstTrough, secondTrough)
        let peakHeight = calculatePeakHeight(prices)
        return (troughSimilarity + peakHeight) / 2.0
    }

    private func calculatePriceFit(_ prices: [Double], _ upperTrend: (slope: Double, intercept: Double), _ lowerTrend: (slope: Double, intercept: Double)) -> Double {
        var fitScore = 0.0

        for (i, price) in prices.enumerated() {
            let upperValue = upperTrend.slope * Double(i) + upperTrend.intercept
            let lowerValue = lowerTrend.slope * Double(i) + lowerTrend.intercept

            if price <= upperValue && price >= lowerValue {
                fitScore += 1.0
            }
        }

        return fitScore / Double(prices.count)
    }

    private func calculateChannelWidth(_ upperChannel: (slope: Double, intercept: Double), _ lowerChannel: (slope: Double, intercept: Double), _ length: Int) -> Double {
        let midPoint = length / 2
        let upperValue = upperChannel.slope * Double(midPoint) + upperChannel.intercept
        let lowerValue = lowerChannel.slope * Double(midPoint) + lowerChannel.intercept
        return abs(upperValue - lowerValue) / upperValue
    }

    private func calculateValleyDepth(_ prices: [Double]) -> Double {
        let peaks = findPeaks(in: prices)
        let troughs = findTroughs(in: prices)

        guard !peaks.isEmpty && !troughs.isEmpty else { return 0.0 }

        let avgPeak = peaks.reduce(0, +) / Double(peaks.count)
        let avgTrough = troughs.reduce(0, +) / Double(troughs.count)

        return (avgPeak - avgTrough) / avgPeak
    }

    private func calculatePeakHeight(_ prices: [Double]) -> Double {
        let peaks = findPeaks(in: prices)
        let troughs = findTroughs(in: prices)

        guard !peaks.isEmpty && !troughs.isEmpty else { return 0.0 }

        let avgPeak = peaks.reduce(0, +) / Double(peaks.count)
        let avgTrough = troughs.reduce(0, +) / Double(troughs.count)

        return (avgPeak - avgTrough) / avgTrough
    }

    private func findSupportLevels(_ lows: [Double]) -> [(price: Double, strength: Double)] {
        var levels: [(price: Double, strength: Double)] = []
        let tolerance = 0.02

        for i in 0..<lows.count {
            let currentLow = lows[i]
            var touches = 1

            for j in (i+1)..<lows.count {
                if abs(lows[j] - currentLow) / currentLow < tolerance {
                    touches += 1
                }
            }

            if touches >= 2 {
                let strength = Double(touches) / Double(lows.count)
                levels.append((currentLow, strength))
            }
        }

        return levels.sorted { $0.strength > $1.strength }
    }

    private func findResistanceLevels(_ highs: [Double]) -> [(price: Double, strength: Double)] {
        var levels: [(price: Double, strength: Double)] = []
        let tolerance = 0.02

        for i in 0..<highs.count {
            let currentHigh = highs[i]
            var touches = 1

            for j in (i+1)..<highs.count {
                if abs(highs[j] - currentHigh) / currentHigh < tolerance {
                    touches += 1
                }
            }

            if touches >= 2 {
                let strength = Double(touches) / Double(highs.count)
                levels.append((currentHigh, strength))
            }
        }

        return levels.sorted { $0.strength > $1.strength }
    }
}

public enum PatternDetectionError: Error {
    case insufficientData
    case invalidPattern
    case calculationError
    case storageNotAvailable
}
