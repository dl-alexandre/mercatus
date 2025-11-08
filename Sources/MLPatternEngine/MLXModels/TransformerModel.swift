import Foundation
import MLX
import MLXNN
import Utils

public class PositionalEncoding: Module {
    private let dModel: Int
    private let maxLen: Int
    private let pe: MLXArray

    public init(dModel: Int, maxLen: Int = 5000) {
        self.dModel = dModel
        self.maxLen = maxLen
        let pe = PositionalEncoding.createPositionalEncoding(dModel: dModel, maxLen: maxLen)
        self.pe = pe
        super.init()
    }

    private static func createPositionalEncoding(dModel: Int, maxLen: Int) -> MLXArray {
        let pe = MLXArray.zeros([maxLen, dModel])

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

public class MultiHeadAttention: Module {
    @ModuleInfo var qLinear: Linear
    @ModuleInfo var kLinear: Linear
    @ModuleInfo var vLinear: Linear
    @ModuleInfo var outLinear: Linear

    private let dModel: Int
    private let numHeads: Int
    private let dK: Int

    public init(dModel: Int, numHeads: Int) {
        self.dModel = dModel
        self.numHeads = numHeads
        self.dK = dModel / numHeads

        self.qLinear = Linear(dModel, dModel)
        self.kLinear = Linear(dModel, dModel)
        self.vLinear = Linear(dModel, dModel)
        self.outLinear = Linear(dModel, dModel)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let batchSize = x.shape[0]
        let seqLen = x.shape[1]

        let q = qLinear(x)
        let k = kLinear(x)
        let v = vLinear(x)

        let qReshaped = q.reshaped([batchSize, seqLen, numHeads, dK]).transposed(0, 2, 1, 3)
        let kReshaped = k.reshaped([batchSize, seqLen, numHeads, dK]).transposed(0, 2, 1, 3)
        let vReshaped = v.reshaped([batchSize, seqLen, numHeads, dK]).transposed(0, 2, 1, 3)

        let scores = (qReshaped * kReshaped.transposed(0, 1, 3, 2)) / MLXArray(sqrt(Float(dK)))
        let attn = softmax(scores, axis: -1)
        let out = attn * vReshaped

        let outTransposed = out.transposed(0, 2, 1, 3)
        let outReshaped = outTransposed.reshaped([batchSize, seqLen, dModel])

        return outLinear(outReshaped)
    }
}

public class TransformerEncoderLayer: Module {
    @ModuleInfo var selfAttn: MultiHeadAttention
    @ModuleInfo var feedForward1: Linear
    @ModuleInfo var feedForward2: Linear
    @ModuleInfo var norm1: LayerNorm
    @ModuleInfo var norm2: LayerNorm
    @ModuleInfo var dropout1: Dropout
    @ModuleInfo var dropout2: Dropout

    private let dModel: Int
    private let dFF: Int

    public init(dModel: Int, numHeads: Int, dFF: Int, dropout: Float = 0.1) {
        self.dModel = dModel
        self.dFF = dFF

        self.selfAttn = MultiHeadAttention(dModel: dModel, numHeads: numHeads)
        self.feedForward1 = Linear(dModel, dFF)
        self.feedForward2 = Linear(dFF, dModel)
        self.norm1 = LayerNorm(dimensions: dModel)
        self.norm2 = LayerNorm(dimensions: dModel)
        self.dropout1 = Dropout(p: dropout)
        self.dropout2 = Dropout(p: dropout)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let attnOut = selfAttn(x)
        let x1 = norm1(x + dropout1(attnOut))

        let ffOut = feedForward2(relu(feedForward1(x1)))
        let x2 = norm2(x1 + dropout2(ffOut))

        return x2
    }
}

public class TransformerEncoder: Module {
    @ModuleInfo var inputEmbedding: Linear
    @ModuleInfo var posEncoding: PositionalEncoding
    @ModuleInfo var layers: [TransformerEncoderLayer]
    @ModuleInfo var outputLayer: Linear

    private let dModel: Int
    private let numLayers: Int

    public init(inputSize: Int, dModel: Int = 128, numHeads: Int = 8, numLayers: Int = 4, dFF: Int = 512, dropout: Float = 0.1, outputSize: Int = 1) {
        self.dModel = dModel
        self.numLayers = numLayers

        self.inputEmbedding = Linear(inputSize, dModel)
        self.posEncoding = PositionalEncoding(dModel: dModel)

        var encoderLayers: [TransformerEncoderLayer] = []
        for _ in 0..<numLayers {
            encoderLayers.append(TransformerEncoderLayer(dModel: dModel, numHeads: numHeads, dFF: dFF, dropout: dropout))
        }
        self.layers = encoderLayers

        self.outputLayer = Linear(dModel, outputSize)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let embedded = inputEmbedding(x)
        let posEncoded = posEncoding(embedded)

        var out = posEncoded
        for layer in layers {
            out = layer(out)
        }

        let pooled = out.mean(axis: 1)
        return outputLayer(pooled)
    }
}

@available(*, deprecated, message: "Use TFTForecaster instead")
public class TransformerForecaster {
    private let model: TransformerEncoder
    private let logger: StructuredLogger

    public init(inputSize: Int, dModel: Int = 128, numHeads: Int = 8, numLayers: Int = 4, logger: StructuredLogger) {
        self.model = TransformerEncoder(inputSize: inputSize, dModel: dModel, numHeads: numHeads, numLayers: numLayers)
        self.logger = logger
    }

    public func predict(data: [[Float]], sequenceLength: Int = 30) -> [[Float]] {
        let paddedData = padSequence(data, maxLength: sequenceLength)
        let flatInput: [Float] = paddedData.flatMap { $0 }
        let input = MLXArray(flatInput, [1, sequenceLength, paddedData[0].count])
        let pred = model(input)
        return [pred[0].asArray(Float.self)]
    }

    private func padSequence(_ data: [[Float]], maxLength: Int) -> [[Float]] {
        var padded = data
        if padded.count < maxLength {
            let padding = Array(repeating: Array(repeating: Float(0.0), count: data[0].count), count: maxLength - padded.count)
            padded = padding + padded
        } else {
            padded = Array(padded.suffix(maxLength))
        }
        return padded
    }
}
