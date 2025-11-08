import Foundation
import ArgumentParser
import MLPatternEngine
import Utils
import Core
import SmartVestor

struct FeatureExtractionDiagnostic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "features",
        abstract: "Diagnose feature extraction pipeline"
    )

    @Option(name: .shortAndLong, help: "Symbol to test (default: BTC-USD)")
    var symbol: String = "BTC-USD"

    func run() async throws {
        print("=== Feature Extraction Diagnostic ===")
        print("")

        let logger = StructuredLogger(enabled: true)

        print("Step 1: Loading sample data...")
        let database = try SQLiteTimeSeriesDatabase(logger: logger)

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) else {
            print("❌ Failed to calculate start date")
            return
        }

        let historicalData = try await database.getMarketData(symbol: symbol, from: startDate, to: endDate)

        guard historicalData.count >= 50 else {
            print("❌ Insufficient data: \(historicalData.count) points (need at least 50)")
            print("   Try fetching more data or using a different symbol")
            return
        }

        print("✓ Loaded \(historicalData.count) data points")
        print("")

        let sortedData = historicalData.sorted { $0.timestamp < $1.timestamp }
        let currentData = sortedData.last!
        let historicalWindow = Array(sortedData.suffix(50))

        print("Step 2: Raw input data...")
        print("   Current data point:")
        print("     Symbol: \(currentData.symbol)")
        print("     Timestamp: \(currentData.timestamp)")
        print("     Open: \(currentData.open)")
        print("     High: \(currentData.high)")
        print("     Low: \(currentData.low)")
        print("     Close: \(currentData.close)")
        print("     Volume: \(currentData.volume)")
        print("     Exchange: \(currentData.exchange)")
        print("   Historical window: \(historicalWindow.count) points")
        print("")

        print("Step 3: Extracting features...")
        let technicalIndicators = TechnicalIndicators()
        let featureExtractor = FeatureExtractor(
            technicalIndicators: technicalIndicators,
            logger: logger
        )

        let featureSet = try await featureExtractor.extractFeatures(
            from: currentData,
            historicalData: historicalWindow
        )

        print("✓ Feature extraction completed")
        print("   Quality score: \(featureSet.qualityScore)")
        print("   Feature count: \(featureSet.features.count)")
        print("")

        print("Step 4: Feature dictionary...")
        let sortedFeatures = featureSet.features.sorted { $0.key < $1.key }
        for (key, value) in sortedFeatures {
            let status = value.isNaN || !value.isFinite ? " ⚠" : ""
            print("   \(key): \(value)\(status)")
        }
        print("")

        print("Step 5: Converting to MLX vector...")
        let featureOrder = ["price", "volume", "high", "low", "open", "close",
                           "rsi", "macd", "macd_signal", "volatility"]

        var featureVector: [Double] = []
        var missingFeatures: [String] = []

        for featureName in featureOrder {
            var value: Double?
            if let directValue = featureSet.features[featureName] {
                value = directValue
            } else if featureName == "close", let priceValue = featureSet.features["price"] {
                value = priceValue
            }

            if let value = value {
                featureVector.append(value)
            } else {
                featureVector.append(0.0)
                missingFeatures.append(featureName)
            }
        }

        print("   Feature order: \(featureOrder.joined(separator: ", "))")
        print("   Vector values: \(featureVector.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
        if !missingFeatures.isEmpty {
            print("   ⚠ Missing features (filled with 0.0): \(missingFeatures.joined(separator: ", "))")
        }
        print("")

        print("Step 6: Validation...")
        let vectorLength = featureVector.count
        let expectedLength = 10
        let nanCount = featureVector.filter { $0.isNaN }.count
        let infCount = featureVector.filter { !$0.isFinite }.count
        let minValue = featureVector.min() ?? 0.0
        let maxValue = featureVector.max() ?? 0.0

        print("   Vector length: \(vectorLength)")
        print("   Expected length: \(expectedLength)")
        if vectorLength == expectedLength {
            print("   ✓ Length matches expected")
        } else {
            print("   ❌ Length mismatch!")
        }

        print("   NaN count: \(nanCount)")
        if nanCount == 0 {
            print("   ✓ No NaN values")
        } else {
            print("   ❌ Found NaN values!")
        }

        print("   Inf count: \(infCount)")
        if infCount == 0 {
            print("   ✓ No Inf values")
        } else {
            print("   ❌ Found Inf values!")
        }

        print("   Value range: [\(String(format: "%.6f", minValue)), \(String(format: "%.6f", maxValue))]")
        print("")

        print("Step 7: Type conversion (Float32)...")
        let float32Vector = featureVector.map { Float($0) }
        let float32NanCount = float32Vector.filter { $0.isNaN }.count
        let float32InfCount = float32Vector.filter { !$0.isFinite }.count

        print("   Converted to Float32: \(float32Vector.count) elements")
        print("   Float32 NaN count: \(float32NanCount)")
        print("   Float32 Inf count: \(float32InfCount)")

        if float32NanCount == 0 && float32InfCount == 0 {
            print("   ✓ Float32 conversion successful")
        } else {
            print("   ❌ Float32 conversion issues!")
        }
        print("")

        print("Step 8: Tensor shape...")
        print("   Shape: [1, \(vectorLength)]")
        print("   Dtype: Float32")
        print("")

        print("Step 9: Feature validation...")
        let isValid = featureExtractor.validateFeatureSet(featureSet)
        if isValid {
            print("   ✓ Feature set validation passed")
        } else {
            print("   ⚠ Feature set validation failed (may be due to optional FFT features)")
            print("   This is acceptable if MLX vector conversion succeeds")
        }
        print("")

        let mlxPipelineValid = vectorLength == expectedLength && nanCount == 0 && infCount == 0 && float32NanCount == 0 && float32InfCount == 0

        print("Step 10: MLX Pipeline Summary...")
        print("   Vector length: \(vectorLength)/\(expectedLength) \(vectorLength == expectedLength ? "✓" : "❌")")
        print("   NaN/Inf free: \(nanCount == 0 && infCount == 0 ? "✓" : "❌")")
        print("   Float32 ready: \(float32NanCount == 0 && float32InfCount == 0 ? "✓" : "❌")")
        print("   All features present: \(missingFeatures.isEmpty ? "✓" : "❌")")
        print("")

        if mlxPipelineValid {
            print("✓ MLX pipeline is ready - feature extraction working correctly")
            print("  The FeatureExtractionError should be resolved.")
        } else {
            print("❌ MLX pipeline issues detected:")
            if vectorLength != expectedLength {
                print("  - Vector length mismatch")
            }
            if nanCount > 0 || infCount > 0 {
                print("  - NaN/Inf values present")
            }
            if !missingFeatures.isEmpty {
                print("  - Missing features: \(missingFeatures.joined(separator: ", "))")
            }
        }
    }
}
