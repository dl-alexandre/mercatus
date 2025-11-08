import Foundation
import Accelerate
import Utils

public protocol FFTAnalyzerProtocol {
    func analyzeFrequencies(timeSeries: [Double], sampleRate: Double) throws -> FFTAnalysisResult
    func extractDominantFrequencies(timeSeries: [Double], sampleRate: Double, maxFrequencies: Int) throws -> [DominantFrequency]
    func calculateSpectralPower(timeSeries: [Double], sampleRate: Double) throws -> SpectralPowerAnalysis
    func detectCyclicPatterns(timeSeries: [Double], sampleRate: Double) throws -> [CyclicPattern]
    func calculatePhaseAlignment(series1: [Double], series2: [Double], sampleRate: Double) throws -> PhaseAlignment
}

public struct FFTAnalysisResult {
    public let frequencies: [Double]
    public let magnitudes: [Double]
    public let phases: [Double]
    public let dominantFrequencies: [DominantFrequency]
    public let spectralPower: SpectralPowerAnalysis
    public let cyclicPatterns: [CyclicPattern]
    public let totalEnergy: Double
    public let peakFrequency: Double?

    public init(
        frequencies: [Double],
        magnitudes: [Double],
        phases: [Double],
        dominantFrequencies: [DominantFrequency],
        spectralPower: SpectralPowerAnalysis,
        cyclicPatterns: [CyclicPattern],
        totalEnergy: Double,
        peakFrequency: Double?
    ) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.phases = phases
        self.dominantFrequencies = dominantFrequencies
        self.spectralPower = spectralPower
        self.cyclicPatterns = cyclicPatterns
        self.totalEnergy = totalEnergy
        self.peakFrequency = peakFrequency
    }
}

public struct DominantFrequency {
    public let frequency: Double
    public let magnitude: Double
    public let phase: Double
    public let period: Double
    public let significance: Double

    public init(frequency: Double, magnitude: Double, phase: Double, period: Double, significance: Double) {
        self.frequency = frequency
        self.magnitude = magnitude
        self.phase = phase
        self.period = period
        self.significance = significance
    }
}

public struct SpectralPowerAnalysis {
    public let lowFrequencyPower: Double
    public let midFrequencyPower: Double
    public let highFrequencyPower: Double
    public let noiseLevel: Double
    public let signalToNoiseRatio: Double

    public init(
        lowFrequencyPower: Double,
        midFrequencyPower: Double,
        highFrequencyPower: Double,
        noiseLevel: Double,
        signalToNoiseRatio: Double
    ) {
        self.lowFrequencyPower = lowFrequencyPower
        self.midFrequencyPower = midFrequencyPower
        self.highFrequencyPower = highFrequencyPower
        self.noiseLevel = noiseLevel
        self.signalToNoiseRatio = signalToNoiseRatio
    }
}

public struct CyclicPattern {
    public let period: Double
    public let strength: Double
    public let phase: Double
    public let periodType: PeriodType

    public enum PeriodType {
        case veryShort
        case short
        case medium
        case long
        case veryLong
        case unknown
    }

    public init(period: Double, strength: Double, phase: Double, periodType: PeriodType) {
        self.period = period
        self.strength = strength
        self.phase = phase
        self.periodType = periodType
    }
}

public struct PhaseAlignment {
    public let correlation: Double
    public let phaseDifference: Double
    public let coherence: Double
    public let alignmentStrength: Double

    public init(
        correlation: Double,
        phaseDifference: Double,
        coherence: Double,
        alignmentStrength: Double
    ) {
        self.correlation = correlation
        self.phaseDifference = phaseDifference
        self.coherence = coherence
        self.alignmentStrength = alignmentStrength
    }
}

public class FFTAnalyzer: FFTAnalyzerProtocol {
    private let logger: StructuredLogger
    private let recursionLock = NSLock()
    private var inRecursion = false

    public init(logger: StructuredLogger = StructuredLogger()) {
        self.logger = logger
    }

    public func analyzeFrequencies(timeSeries: [Double], sampleRate: Double) throws -> FFTAnalysisResult {
        recursionLock.lock()
        guard !inRecursion else {
            recursionLock.unlock()
            logger.error(component: "FFTAnalyzer", event: "FFT recursion detected - breaking cycle")
            throw FFTAnalysisError.calculationError
        }
        inRecursion = true
        recursionLock.unlock()
        defer {
            recursionLock.lock()
            inRecursion = false
            recursionLock.unlock()
        }
        guard timeSeries.count >= 8 else {
            throw FFTAnalysisError.insufficientData
        }

        let paddedLength = nextPowerOfTwo(timeSeries.count)
        let normalizedSeries = normalizeTimeSeries(timeSeries)

        var realInput = normalizedSeries
        realInput.append(contentsOf: Array(repeating: 0.0, count: paddedLength - timeSeries.count))
        var imaginaryInput = Array(repeating: 0.0, count: paddedLength)

        guard realInput.count == imaginaryInput.count, realInput.count == paddedLength else {
            throw FFTAnalysisError.calculationError
        }

        let log2n = vDSP_Length(log2(Double(paddedLength)) / log2(2.0))
        let computedLength = pow(2, Double(log2n))
        guard abs(computedLength - Double(paddedLength)) < 1e-10 else {
            throw FFTAnalysisError.invalidFFTSize
        }

        let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2))
        guard let fftSetup = fftSetup else {
            throw FFTAnalysisError.calculationError
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        let fftSize = paddedLength / 2
        var magnitudes = Array(repeating: 0.0, count: fftSize)
        var phases = Array(repeating: 0.0, count: fftSize)
        var frequencies = Array(repeating: 0.0, count: fftSize)

        realInput.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryInput.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else {
                    return
                }

                var complexSignal = DSPDoubleSplitComplex(
                    realp: realBase,
                    imagp: imagBase
                )

                vDSP_fft_zipD(fftSetup, &complexSignal, 1, log2n, FFTDirection(FFT_FORWARD))

                var tempMagnitude = [Double](repeating: 0, count: fftSize)
                vDSP_zvmagsD(&complexSignal, 1, &tempMagnitude, 1, vDSP_Length(fftSize))

                for i in 0..<fftSize {
                    let real = complexSignal.realp[i]
                    let imag = complexSignal.imagp[i]
                    magnitudes[i] = sqrt(tempMagnitude[i])
                    phases[i] = atan2(imag, real)
                    frequencies[i] = Double(i) * sampleRate / Double(paddedLength)
                }
            }
        }

        let dominantFrequencies = try extractDominantFrequencies(
            timeSeries: timeSeries,
            sampleRate: sampleRate,
            maxFrequencies: 5
        )

        let spectralPower = calculateSpectralPower(
            fromSpectrum: frequencies,
            magnitudes: magnitudes,
            sampleRate: sampleRate
        )

        let cyclicPatterns = try detectCyclicPatterns(
            timeSeries: timeSeries,
            sampleRate: sampleRate
        )

        let totalEnergy = magnitudes.reduce(0) { $0 + $1 * $1 }
        let peakFrequency = dominantFrequencies.first?.frequency

        return FFTAnalysisResult(
            frequencies: frequencies,
            magnitudes: magnitudes,
            phases: phases,
            dominantFrequencies: dominantFrequencies,
            spectralPower: spectralPower,
            cyclicPatterns: cyclicPatterns,
            totalEnergy: totalEnergy,
            peakFrequency: peakFrequency
        )
    }

    public func extractDominantFrequencies(
        timeSeries: [Double],
        sampleRate: Double,
        maxFrequencies: Int
    ) throws -> [DominantFrequency] {
        guard timeSeries.count >= 8 else {
            throw FFTAnalysisError.insufficientData
        }

        let paddedLength = nextPowerOfTwo(timeSeries.count)
        guard paddedLength >= 8 else {
            throw FFTAnalysisError.invalidFFTSize
        }
        guard paddedLength.isMultiple(of: 2) else {
            throw FFTAnalysisError.invalidFFTSize
        }

        let normalizedSeries = normalizeTimeSeries(timeSeries)

        var realInput = normalizedSeries
        realInput.append(contentsOf: Array(repeating: 0.0, count: paddedLength - timeSeries.count))
        var imaginaryInput = Array(repeating: 0.0, count: paddedLength)

        guard realInput.count == imaginaryInput.count else {
            throw FFTAnalysisError.calculationError
        }
        guard realInput.count == paddedLength else {
            throw FFTAnalysisError.calculationError
        }

        let log2n = vDSP_Length(log2(Double(paddedLength)) / log2(2.0))
        let computedLength = pow(2, Double(log2n))
        guard abs(computedLength - Double(paddedLength)) < 1e-10 else {
            throw FFTAnalysisError.invalidFFTSize
        }

        let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2))
        guard let fftSetup = fftSetup else {
            throw FFTAnalysisError.calculationError
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        let fftSize = paddedLength / 2
        var magnitudes = [Double]()
        var phases = [Double]()
        var frequencies = [Double]()
        var tempMagnitude = [Double](repeating: 0, count: fftSize)

        realInput.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryInput.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else {
                    return
                }

                var complexSignal = DSPDoubleSplitComplex(
                    realp: realBase,
                    imagp: imagBase
                )

                vDSP_fft_zipD(fftSetup, &complexSignal, 1, log2n, FFTDirection(FFT_FORWARD))

                vDSP_zvmagsD(&complexSignal, 1, &tempMagnitude, 1, vDSP_Length(fftSize))

                for i in 0..<fftSize {
                    let real = complexSignal.realp[i]
                    let imag = complexSignal.imagp[i]
                    let magnitude = sqrt(tempMagnitude[i])
                    let phase = atan2(imag, real)
                    let frequency = Double(i) * sampleRate / Double(paddedLength)

                    magnitudes.append(magnitude)
                    phases.append(phase)
                    frequencies.append(frequency)
                }
            }
        }

        var frequencyData: [(index: Int, magnitude: Double, phase: Double, frequency: Double)] = []
        for i in 1..<fftSize {
            frequencyData.append((i, magnitudes[i], phases[i], frequencies[i]))
        }

        frequencyData.sort { $0.magnitude > $1.magnitude }

        let topFrequencies = Array(frequencyData.prefix(min(maxFrequencies, frequencyData.count)))
        let totalPower = magnitudes.reduce(0) { $0 + $1 * $1 }

        return topFrequencies.map { data in
            let period = data.frequency > 0 ? 1.0 / data.frequency : 0.0
            let significance = data.magnitude * data.magnitude / max(totalPower, 1e-10)

            return DominantFrequency(
                frequency: data.frequency,
                magnitude: data.magnitude,
                phase: data.phase,
                period: period,
                significance: significance
            )
        }
    }

    public func calculateSpectralPower(
        timeSeries: [Double],
        sampleRate: Double
    ) throws -> SpectralPowerAnalysis {
        guard timeSeries.count >= 8 else {
            throw FFTAnalysisError.insufficientData
        }

        let paddedLength = nextPowerOfTwo(timeSeries.count)
        guard paddedLength >= 8 else {
            throw FFTAnalysisError.invalidFFTSize
        }
        guard paddedLength.isMultiple(of: 2) else {
            throw FFTAnalysisError.invalidFFTSize
        }

        let normalizedSeries = normalizeTimeSeries(timeSeries)

        var realInput = normalizedSeries
        realInput.append(contentsOf: Array(repeating: 0.0, count: paddedLength - timeSeries.count))
        var imaginaryInput = Array(repeating: 0.0, count: paddedLength)

        guard realInput.count == imaginaryInput.count else {
            throw FFTAnalysisError.calculationError
        }
        guard realInput.count == paddedLength else {
            throw FFTAnalysisError.calculationError
        }

        let log2n = vDSP_Length(log2(Double(paddedLength)) / log2(2.0))
        let computedLength = pow(2, Double(log2n))
        guard abs(computedLength - Double(paddedLength)) < 1e-10 else {
            throw FFTAnalysisError.invalidFFTSize
        }

        let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2))
        guard let fftSetup = fftSetup else {
            throw FFTAnalysisError.calculationError
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        let fftSize = paddedLength / 2
        var magnitudes = Array(repeating: 0.0, count: fftSize)
        var frequencies = Array(repeating: 0.0, count: fftSize)

        realInput.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryInput.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else {
                    return
                }

                var complexSignal = DSPDoubleSplitComplex(
                    realp: realBase,
                    imagp: imagBase
                )

                vDSP_fft_zipD(fftSetup, &complexSignal, 1, log2n, FFTDirection(FFT_FORWARD))

                var tempMagnitude = [Double](repeating: 0, count: fftSize)
                vDSP_zvmagsD(&complexSignal, 1, &tempMagnitude, 1, vDSP_Length(fftSize))

                for i in 0..<fftSize {
                    magnitudes[i] = sqrt(tempMagnitude[i])
                    frequencies[i] = Double(i) * sampleRate / Double(paddedLength)
                }
            }
        }

        return calculateSpectralPower(
            fromSpectrum: frequencies,
            magnitudes: magnitudes,
            sampleRate: sampleRate
        )
    }

    private func calculateSpectralPower(
        fromSpectrum frequencies: [Double],
        magnitudes: [Double],
        sampleRate: Double
    ) -> SpectralPowerAnalysis {
        let nyquistFrequency = sampleRate / 2.0

        let lowFreqCutoff = nyquistFrequency * 0.1
        let midFreqCutoff = nyquistFrequency * 0.5

        var lowPower: Double = 0
        var midPower: Double = 0
        var highPower: Double = 0
        var allPower: Double = 0

        for i in 0..<frequencies.count {
            let freq = frequencies[i]
            let power = magnitudes[i] * magnitudes[i]
            allPower += power

            if freq <= lowFreqCutoff {
                lowPower += power
            } else if freq <= midFreqCutoff {
                midPower += power
            } else {
                highPower += power
            }
        }

        let noiseLevel = highPower * 0.8
        let signalPower = allPower - noiseLevel
        let snr = noiseLevel > 0 ? signalPower / noiseLevel : 100.0

        return SpectralPowerAnalysis(
            lowFrequencyPower: lowPower / max(allPower, 1e-10),
            midFrequencyPower: midPower / max(allPower, 1e-10),
            highFrequencyPower: highPower / max(allPower, 1e-10),
            noiseLevel: noiseLevel,
            signalToNoiseRatio: snr
        )
    }

    public func detectCyclicPatterns(
        timeSeries: [Double],
        sampleRate: Double
    ) throws -> [CyclicPattern] {
        let dominantFreqs = try extractDominantFrequencies(
            timeSeries: timeSeries,
            sampleRate: sampleRate,
            maxFrequencies: 10
        )

        return dominantFreqs.map { freq in
            let periodType: CyclicPattern.PeriodType
            let periodHours = freq.period * sampleRate / 3600.0

            if periodHours < 6 {
                periodType = .veryShort
            } else if periodHours < 24 {
                periodType = .short
            } else if periodHours < 168 {
                periodType = .medium
            } else if periodHours < 720 {
                periodType = .long
            } else {
                periodType = .veryLong
            }

            return CyclicPattern(
                period: freq.period,
                strength: min(freq.significance * 10.0, 1.0),
                phase: freq.phase,
                periodType: periodType
            )
        }
    }

    public func calculatePhaseAlignment(
        series1: [Double],
        series2: [Double],
        sampleRate: Double
    ) throws -> PhaseAlignment {
        guard series1.count == series2.count, series1.count >= 8 else {
            throw FFTAnalysisError.insufficientData
        }

        let analysis1 = try analyzeFrequencies(timeSeries: series1, sampleRate: sampleRate)
        let analysis2 = try analyzeFrequencies(timeSeries: series2, sampleRate: sampleRate)

        let minLength = min(analysis1.frequencies.count, analysis2.frequencies.count)

        var correlationSum: Double = 0
        var phaseDifferences: [Double] = []
        var coherenceSum: Double = 0

        for i in 0..<minLength {
            let mag1 = analysis1.magnitudes[i]
            let mag2 = analysis2.magnitudes[i]
            let phase1 = analysis1.phases[i]
            let phase2 = analysis2.phases[i]

            correlationSum += mag1 * mag2
            phaseDifferences.append(abs(phase1 - phase2))

            let crossPower = mag1 * mag2
            let autoPower1 = mag1 * mag1
            let autoPower2 = mag2 * mag2
            let coherence = autoPower1 > 0 && autoPower2 > 0 ?
                crossPower / sqrt(autoPower1 * autoPower2) : 0.0
            coherenceSum += coherence
        }

        let correlation = correlationSum / Double(minLength)
        let avgPhaseDiff = phaseDifferences.reduce(0, +) / Double(phaseDifferences.count)
        let coherence = coherenceSum / Double(minLength)
        let alignmentStrength = (1.0 - min(avgPhaseDiff / .pi, 1.0)) * coherence

        return PhaseAlignment(
            correlation: min(max(correlation, 0.0), 1.0),
            phaseDifference: avgPhaseDiff,
            coherence: coherence,
            alignmentStrength: alignmentStrength
        )
    }

    private func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }

    private func normalizeTimeSeries(_ series: [Double]) -> [Double] {
        guard !series.isEmpty else { return [] }

        let mean = series.reduce(0, +) / Double(series.count)
        let variance = series.map { pow($0 - mean, 2) }.reduce(0, +) / Double(series.count)
        let stdDev = sqrt(variance)

        guard stdDev > 1e-10 else {
            return Array(repeating: 0.0, count: series.count)
        }

        return series.map { ($0 - mean) / stdDev }
    }
}

public enum FFTAnalysisError: Error {
    case insufficientData
    case invalidFFTSize
    case calculationError
}
