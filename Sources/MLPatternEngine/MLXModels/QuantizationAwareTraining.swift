import Foundation
import MLX
import MLXNN
import MLXOptimizers
import Utils

public class QuantizationAwareModel: Module {
    @ModuleInfo var quantizedLinear1: QuantizedLinear
    @ModuleInfo var quantizedLinear2: QuantizedLinear
    @ModuleInfo var quantizedLinear3: QuantizedLinear
    @ModuleInfo var dropout1: Dropout
    @ModuleInfo var dropout2: Dropout

    private let inputSize: Int
    private let logger: StructuredLogger

    public init(inputSize: Int = 18, hiddenSize1: Int = 128, hiddenSize2: Int = 64, logger: StructuredLogger, groupSize: Int = 64, bits: Int = 8) {
        self.inputSize = inputSize
        self.logger = logger

        let scale1 = sqrt(1.0 / Float(inputSize))
        let scale2 = sqrt(1.0 / Float(hiddenSize1))
        let scale3 = sqrt(1.0 / Float(hiddenSize2))

        let w1 = MLXRandom.normal([inputSize, hiddenSize1]) * scale1
        let b1 = MLXArray.zeros([hiddenSize1])
        let w2 = MLXRandom.normal([hiddenSize1, hiddenSize2]) * scale2
        let b2 = MLXArray.zeros([hiddenSize2])
        let w3 = MLXRandom.normal([hiddenSize2, 1]) * scale3
        let b3 = MLXArray.zeros([1])

        self.quantizedLinear1 = QuantizedLinear(weight: w1, bias: b1, groupSize: groupSize, bits: bits)
        self.dropout1 = Dropout(p: 0.2)
        self.quantizedLinear2 = QuantizedLinear(weight: w2, bias: b2, groupSize: groupSize, bits: bits)
        self.dropout2 = Dropout(p: 0.2)
        self.quantizedLinear3 = QuantizedLinear(weight: w3, bias: b3, groupSize: groupSize, bits: bits)

        super.init()

        logger.info(component: "QuantizationAwareModel", event: "QAT model initialized", data: [
            "groupSize": String(groupSize),
            "bits": String(bits)
        ])
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let x1 = relu(quantizedLinear1(x))
        let x1Drop = dropout1(x1)
        let x2 = relu(quantizedLinear2(x1Drop))
        let x2Drop = dropout2(x2)
        let x3 = quantizedLinear3(x2Drop)
        return x3
    }
}

public class QATTrainer {
    private let model: QuantizationAwareModel
    private let logger: StructuredLogger

    public init(inputSize: Int = 18, logger: StructuredLogger, groupSize: Int = 64, bits: Int = 8) {
        self.model = QuantizationAwareModel(inputSize: inputSize, logger: logger, groupSize: groupSize, bits: bits)
        self.logger = logger
    }

    public func train(inputs: [[Double]], targets: [[Double]], epochs: Int = 100, learningRate: Float = 1e-3) async throws {
        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        let flatInputs: [Float] = inputs.flatMap { $0.map(Float.init) }
        let flatTargets: [Float] = targets.flatMap { $0.map(Float.init) }

        let inputArray = MLXArray(flatInputs, [inputs.count, inputShape]).asType(Float.self)
        let targetArray = MLXArray(flatTargets, [targets.count, targets[0].count]).asType(Float.self)

        let optimizer = AdamW(learningRate: learningRate, weightDecay: 1e-4)

        func loss(model: QuantizationAwareModel, x: MLXArray, y: MLXArray) -> MLXArray {
            let preds = model(x)
            let diff = preds - y
            return (diff * diff).mean()
        }

        let lg = valueAndGrad(model: model, loss)

        for epoch in 0..<epochs {
            let (lossValue, grads) = lg(model, inputArray, targetArray)
            optimizer.update(model: model, gradients: grads)

            if epoch % 10 == 0 {
                let lossFloat = lossValue.item(Float.self)
                logger.info(component: "QATTrainer", event: "Training progress", data: [
                    "epoch": String(epoch),
                    "loss": String(lossFloat)
                ])
            }
        }

        logger.info(component: "QATTrainer", event: "QAT training completed")
    }

    public func predict(inputs: [[Double]]) throws -> [[Double]] {
        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        let flatInputs: [Float] = inputs.flatMap { $0.map(Float.init) }
        let inputArray = MLXArray(flatInputs, [inputs.count, inputShape]).asType(Float.self)

        let predictions = model(inputArray)

        try withError { error in
            eval(predictions)
            try error.check()
        }

        let predictionsArray = predictions.asArray(Float.self)
        var results: [[Double]] = []
        for i in 0..<inputs.count {
            results.append([Double(predictionsArray[i])])
        }
        return results
    }
}
