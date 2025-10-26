import Testing
import Foundation
@testable import MLPatternEngine
@testable import MLPatternEngineMLX
@testable import Utils

@Suite("MLX Integration Tests", .disabled("MLX requires special system setup"))
struct MLXIntegrationTests {

    @Test(.disabled("MLX requires metallib"))
    func testMLXPricePredictionModelCreation() async throws {
        let logger = createTestLogger()
        let model = MLXPricePredictionModel(logger: logger)

        let sampleInputs = [
            [100.0, 1000.0, 50.0, 0.1, 0.05, 0.3, 0.2, 0.01, 0.05, 1000000.0],
            [101.0, 1100.0, 55.0, 0.15, 0.08, 0.4, 0.25, 0.02, 0.08, 1100000.0]
        ]

        let sampleTargets = [
            [0.01],
            [0.015]
        ]

        let trainingResult = try await model.train(inputs: sampleInputs, targets: sampleTargets, epochs: 10)

        #expect(trainingResult.finalLoss >= 0.0)
        #expect(trainingResult.bestLoss >= 0.0)
        #expect(trainingResult.epochs == 10)

        let prediction = try await model.predictSingle(input: sampleInputs[0])
        #expect(prediction.isFinite)
    }

    @Test(.disabled("MLX requires metallib"))
    func testMLXPricePredictionModelInfo() async throws {
        let logger = createTestLogger()
        let model = MLXPricePredictionModel(logger: logger)

        let modelInfo = model.getModelInfo()

        #expect(modelInfo.modelType == .pricePrediction)
        #expect(modelInfo.isActive == true)
        #expect(modelInfo.accuracy == 0.85)
    }

    @Test(.disabled("MLX requires metallib"))
    func testMLXPricePredictionBatchPredict() async throws {
        let logger = createTestLogger()
        let model = MLXPricePredictionModel(logger: logger)

        let sampleInputs = [
            [100.0, 1000.0, 50.0, 0.1, 0.05, 0.3, 0.2, 0.01, 0.05, 1000000.0],
            [101.0, 1100.0, 55.0, 0.15, 0.08, 0.4, 0.25, 0.02, 0.08, 1100000.0]
        ]

        let predictions = try await model.predict(inputs: sampleInputs)

        #expect(predictions.count == 2)
        #expect(predictions[0].count == 1)
        #expect(predictions[1].count == 1)
        #expect(predictions[0][0].isFinite)
        #expect(predictions[1][0].isFinite)
    }
}
