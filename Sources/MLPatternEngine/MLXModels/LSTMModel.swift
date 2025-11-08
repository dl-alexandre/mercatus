// LSTM Model for time series forecasting in portfolio analysis
// Implements multi-step ahead price prediction using MLX

import Foundation
import MLX
import MLXNN
import MLXOptimizers
import Utils

public class AttentionLayer: Module {
    @ModuleInfo var query: Linear
    @ModuleInfo var key: Linear
    @ModuleInfo var value: Linear
    @ModuleInfo var output: Linear

    private let dModel: Int

    public init(dModel: Int) {
        self.dModel = dModel
        self.query = Linear(dModel, dModel)
        self.key = Linear(dModel, dModel)
        self.value = Linear(dModel, dModel)
        self.output = Linear(dModel, dModel)
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let q = query(x)
        let k = key(x)
        let v = value(x)

        let scale = MLXArray(Float(1.0) / sqrt(Float(dModel)))
        let scores = (q * k.transposed()) * scale
        let attn = softmax(scores, axis: -1)
        let attended = attn * v
        return output(attended)
    }
}

public class SinusoidalPositionalEncoding: Module {
    private let dModel: Int
    private let maxLen: Int
    private let pe: MLXArray

    public init(dModel: Int, maxLen: Int = 5000) {
        self.dModel = dModel
        self.maxLen = maxLen
        let pe = SinusoidalPositionalEncoding.createPositionalEncoding(dModel: dModel, maxLen: maxLen)
        self.pe = pe
        super.init()
    }

    private static func createPositionalEncoding(dModel: Int, maxLen: Int) -> MLXArray {
        var pe = MLXArray.zeros([maxLen, dModel])

        for pos in 0..<maxLen {
            for i in 0..<(dModel / 2) {
                let divTerm = pow(10000.0, Float(2 * i) / Float(dModel))
                let posFloat = Float(pos)
                pe[pos, 2 * i] = MLXArray(sin(posFloat / divTerm))
                pe[pos, 2 * i + 1] = MLXArray(cos(posFloat / divTerm))
            }
        }

        return pe
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let seqLen = x.shape[1]
        let posEnc = pe[0..<seqLen]
        return x + posEnc
    }
}

public class LSTMModel: Module {
    @ModuleInfo var lstm1: LSTM
    @ModuleInfo var dropout1: Dropout
    @ModuleInfo var attention: AttentionLayer
    @ModuleInfo var posEncoding: SinusoidalPositionalEncoding
    @ModuleInfo var lstm2: LSTM
    @ModuleInfo var dropout2: Dropout
    @ModuleInfo var dense: Linear

    public init(sequenceLength: Int, nFeatures: Int, nOutputs: Int = 1, useAttention: Bool = true, usePositionalEncoding: Bool = true) {
        self.lstm1 = LSTM(inputSize: nFeatures, hiddenSize: 50)
        self.dropout1 = Dropout(p: 0.2)
        self.attention = AttentionLayer(dModel: 50)
        self.posEncoding = SinusoidalPositionalEncoding(dModel: 50, maxLen: sequenceLength)
        self.lstm2 = LSTM(inputSize: 50, hiddenSize: 50)
        self.dropout2 = Dropout(p: 0.2)
        self.dense = Linear(50, nOutputs)
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (x1, _) = lstm1(x)
        let x2 = relu(x1)
        let x3 = dropout1(x2)
        let x4 = attention(x3)
        let x4Pos = posEncoding(x4)
        let (x5, _) = lstm2(x4Pos)
        let x6 = relu(x5)
        let x7 = dropout2(x6)
        return dense(x7)
    }
}

public class PortfolioLSTMForecaster {
    private let model: LSTMModel
    private let optimizer: Adam
    private let logger: StructuredLogger

    public init(sequenceLength: Int, nFeatures: Int, nOutputs: Int = 1, logger: StructuredLogger) {
        self.model = LSTMModel(sequenceLength: sequenceLength, nFeatures: nFeatures, nOutputs: nOutputs)
        self.optimizer = Adam(learningRate: 0.001)
        self.logger = logger
    }

    public func train(data: [[Float]], epochs: Int = 50) throws {
        logger.info(component: "PortfolioLSTMForecaster", event: "Starting LSTM training",
                   data: ["epochs": String(epochs), "dataPoints": String(data.count)])

        let (X, y) = createSequences(data: data, sequenceLength: 30)  // 30-day sequences

        for epoch in 0..<epochs {
            // Ensure Float32 arrays (Metal doesn't support Float64)
            let flatX: [Float] = X.flatMap { $0.flatMap { $0 } }
            let flatY: [Float] = y.flatMap { $0 }
            let XArray = MLXArray(flatX, [X.count, 30, data[0].count])
            let yArray = MLXArray(flatY, [y.count, data[0].count])

            func loss(model: LSTMModel, x: MLXArray, y: MLXArray) -> MLXArray {
                let diff = model(x) - y
                let two = MLXArray(Float(2.0))
                let squared = pow(diff, two)
                return squared.mean()
            }

            let lg = valueAndGrad(model: model, loss)
            let (lossValue, grads) = lg(model, XArray, yArray)
            optimizer.update(model: model, gradients: grads)

            if epoch % 10 == 0 {
                let lossFloat = lossValue.item(Float.self)
                logger.info(component: "PortfolioLSTMForecaster", event: "Training progress",
                           data: ["epoch": String(epoch), "loss": String(lossFloat)])
            }
        }

        logger.info(component: "PortfolioLSTMForecaster", event: "LSTM training completed")
    }

    public func predict(data: [[Float]], forecastHorizon: Int = 10) -> [[Float]] {
        var predictions: [[Float]] = []
        var currentSequence = Array(data.suffix(30))  // Last 30 days

        for _ in 0..<forecastHorizon {
            let flatInput: [Float] = currentSequence.flatMap { $0 }
            let input = MLXArray(flatInput, [1, 30, data[0].count])
            let pred = model(input)
            let predValues = pred[0].asArray(Float.self)

            predictions.append(predValues)
            // Roll the sequence: remove first, add prediction
            currentSequence.removeFirst()
            currentSequence.append(predValues)
        }

        return predictions
    }

    public func padSequences(sequences: [[[Float]]], maxLength: Int, paddingValue: Float = 0.0) -> [[[Float]]] {
        return sequences.map { sequence in
            var padded = sequence
            while padded.count < maxLength {
                padded.insert(Array(repeating: paddingValue, count: sequence[0].count), at: 0)
            }
            return Array(padded.prefix(maxLength))
        }
    }

    public func predictWithPadding(data: [[Float]], maxSequenceLength: Int = 30) -> [[Float]] {
        var paddedData = data
        if paddedData.count < maxSequenceLength {
            let padding = Array(repeating: Array(repeating: Float(0.0), count: data[0].count), count: maxSequenceLength - paddedData.count)
            paddedData = padding + paddedData
        } else {
            paddedData = Array(paddedData.suffix(maxSequenceLength))
        }

        let flatInput: [Float] = paddedData.flatMap { $0 }
        let input = MLXArray(flatInput, [1, maxSequenceLength, data[0].count])
        let pred = model(input)
        return [pred[0].asArray(Float.self)]
    }

    private func createSequences(data: [[Float]], sequenceLength: Int) -> ([[[Float]]], [[Float]]) {
        var X: [[[Float]]] = []
        var y: [[Float]] = []

        for i in 0..<(data.count - sequenceLength) {
            X.append(Array(data[i..<(i + sequenceLength)]))
            y.append(data[i + sequenceLength])
        }

        return (X, y)
    }
}
