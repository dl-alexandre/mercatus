import Foundation
import MLX
import MLXNN
import Utils

private func checkpoint<T>(_ closure: () -> T) -> T {
    return closure()
}

public class TimeEmbedding: Module {
    @ModuleInfo var dayOfWeekEmbedding: Embedding
    @ModuleInfo var hourEmbedding: Embedding
    @ModuleInfo var monthEmbedding: Embedding
    @ModuleInfo var dayOfMonthEmbedding: Embedding
    @ModuleInfo var projection: Linear

    private let dModel: Int

    public init(dModel: Int = 64) {
        self.dModel = dModel

        self.dayOfWeekEmbedding = Embedding(embeddingCount: 7, dimensions: dModel / 4)
        self.hourEmbedding = Embedding(embeddingCount: 24, dimensions: dModel / 4)
        self.monthEmbedding = Embedding(embeddingCount: 12, dimensions: dModel / 4)
        self.dayOfMonthEmbedding = Embedding(embeddingCount: 31, dimensions: dModel / 4)
        self.projection = Linear(dModel, dModel)

        super.init()
    }

    public func callAsFunction(_ timestamps: [Date]) -> MLXArray {
        let calendar = Calendar.current

        var embeddings: [MLXArray] = []

        for timestamp in timestamps {
            let components = calendar.dateComponents([.weekday, .hour, .month, .day], from: timestamp)

            let dayOfWeek = (components.weekday ?? 1) - 1
            let hour = components.hour ?? 0
            let month = (components.month ?? 1) - 1
            let dayOfMonth = (components.day ?? 1) - 1

            let dowEmb = dayOfWeekEmbedding(MLXArray([Int32(dayOfWeek)]))
            let hourEmb = hourEmbedding(MLXArray([Int32(hour)]))
            let monthEmb = monthEmbedding(MLXArray([Int32(month)]))
            let dayEmb = dayOfMonthEmbedding(MLXArray([Int32(dayOfMonth)]))

            let combined = concatenated([dowEmb, hourEmb, monthEmb, dayEmb], axis: -1)
            embeddings.append(combined)
        }

        let stacked = stacked(embeddings, axis: 0)
        return projection(stacked)
    }
}

public class EventEmbedding: Module {
    @ModuleInfo var eventEmbedding: Embedding
    @ModuleInfo var projection: Linear

    private let dModel: Int
    private let numEventTypes: Int

    public init(numEventTypes: Int = 10, dModel: Int = 64) {
        self.numEventTypes = numEventTypes
        self.dModel = dModel

        self.eventEmbedding = Embedding(embeddingCount: numEventTypes, dimensions: dModel)
        self.projection = Linear(dModel, dModel)

        super.init()
    }

    public func callAsFunction(_ eventIds: [Int]) -> MLXArray {
        let eventArray = MLXArray(eventIds.map { Int32($0) })
        let embedded = eventEmbedding(eventArray)
        return projection(embedded)
    }
}

public class VariableSelectionNetwork: Module {
    @ModuleInfo var variableSelector: Linear
    @ModuleInfo var variableTransform: Linear

    private let inputSize: Int
    private let hiddenSize: Int

    public init(inputSize: Int, hiddenSize: Int) {
        self.inputSize = inputSize
        self.hiddenSize = hiddenSize

        self.variableSelector = Linear(inputSize, inputSize)
        self.variableTransform = Linear(inputSize, hiddenSize)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let weights = softmax(variableSelector(x), axis: -1)
        let weighted = x * weights
        return variableTransform(weighted)
    }
}

public class TemporalFusionDecoder: Module {
    @ModuleInfo var staticSelector: VariableSelectionNetwork
    @ModuleInfo var historicalSelector: VariableSelectionNetwork
    @ModuleInfo var futureSelector: VariableSelectionNetwork
    @ModuleInfo var temporalFusion: MultiHeadAttention
    @ModuleInfo var outputLayer: Linear
    @ModuleInfo var quantileLayer10: Linear
    @ModuleInfo var quantileLayer50: Linear
    @ModuleInfo var quantileLayer90: Linear
    @ModuleInfo var horizon1h: Linear
    @ModuleInfo var horizon4h: Linear
    @ModuleInfo var horizon24h: Linear

    private let dModel: Int
    private let numHeads: Int

    public init(dModel: Int = 128, numHeads: Int = 8, staticSize: Int, historicalSize: Int, futureSize: Int) {
        self.dModel = dModel
        self.numHeads = numHeads

        self.staticSelector = VariableSelectionNetwork(inputSize: staticSize, hiddenSize: dModel)
        self.historicalSelector = VariableSelectionNetwork(inputSize: historicalSize, hiddenSize: dModel)
        self.futureSelector = VariableSelectionNetwork(inputSize: futureSize, hiddenSize: dModel)
        self.temporalFusion = MultiHeadAttention(dModel: dModel, numHeads: numHeads)
        self.outputLayer = Linear(dModel, 1)
        self.quantileLayer10 = Linear(dModel, 1)
        self.quantileLayer50 = Linear(dModel, 1)
        self.quantileLayer90 = Linear(dModel, 1)
        self.horizon1h = Linear(dModel, 1)
        self.horizon4h = Linear(dModel, 1)
        self.horizon24h = Linear(dModel, 1)

        super.init()
    }

    public func callAsFunction(staticInputs: MLXArray, historicalInputs: MLXArray, futureInputs: MLXArray, useCheckpointing: Bool = false) -> MLXArray {
        let staticFeatures = staticSelector(staticInputs)

        let historicalFeatures: MLXArray
        let futureFeatures: MLXArray

        if useCheckpointing {
            historicalFeatures = checkpoint { self.historicalSelector(historicalInputs) }
            futureFeatures = checkpoint { self.futureSelector(futureInputs) }
        } else {
            historicalFeatures = historicalSelector(historicalInputs)
            futureFeatures = futureSelector(futureInputs)
        }

        let combined = concatenated([historicalFeatures, futureFeatures], axis: 1)

        let fused: MLXArray
        if useCheckpointing {
            fused = checkpoint { self.temporalFusion(combined) }
        } else {
            fused = temporalFusion(combined)
        }

        let pooled = fused.mean(axis: 1)
        let staticSqueezed = staticFeatures.reshaped([staticFeatures.shape[1]])
        let staticEnhanced = pooled + staticSqueezed

        return outputLayer(staticEnhanced)
    }

    public func callAsFunctionMultiHorizon(staticInputs: MLXArray, historicalInputs: MLXArray, futureInputs: MLXArray, useCheckpointing: Bool = false) -> (horizon1h: MLXArray, horizon4h: MLXArray, horizon24h: MLXArray) {
        let staticFeatures = staticSelector(staticInputs)

        let historicalFeatures: MLXArray
        let futureFeatures: MLXArray

        if useCheckpointing {
            historicalFeatures = checkpoint { self.historicalSelector(historicalInputs) }
            futureFeatures = checkpoint { self.futureSelector(futureInputs) }
        } else {
            historicalFeatures = historicalSelector(historicalInputs)
            futureFeatures = futureSelector(futureInputs)
        }

        let combined = concatenated([historicalFeatures, futureFeatures], axis: 1)

        let fused: MLXArray
        if useCheckpointing {
            fused = checkpoint { self.temporalFusion(combined) }
        } else {
            fused = temporalFusion(combined)
        }

        let pooled = fused.mean(axis: 1)
        let staticSqueezed = staticFeatures.reshaped([staticFeatures.shape[1]])
        let staticEnhanced = pooled + staticSqueezed

        let h1h = horizon1h(staticEnhanced)
        let h4h = horizon4h(staticEnhanced)
        let h24h = horizon24h(staticEnhanced)

        return (h1h, h4h, h24h)
    }

    public func callAsFunctionWithQuantiles(staticInputs: MLXArray, historicalInputs: MLXArray, futureInputs: MLXArray, useCheckpointing: Bool = false) -> (mean: MLXArray, quantile10: MLXArray, quantile50: MLXArray, quantile90: MLXArray) {
        let staticFeatures = staticSelector(staticInputs)

        let historicalFeatures: MLXArray
        let futureFeatures: MLXArray

        if useCheckpointing {
            historicalFeatures = checkpoint { self.historicalSelector(historicalInputs) }
            futureFeatures = checkpoint { self.futureSelector(futureInputs) }
        } else {
            historicalFeatures = historicalSelector(historicalInputs)
            futureFeatures = futureSelector(futureInputs)
        }

        let combined = concatenated([historicalFeatures, futureFeatures], axis: 1)

        let fused: MLXArray
        if useCheckpointing {
            fused = checkpoint { self.temporalFusion(combined) }
        } else {
            fused = temporalFusion(combined)
        }

        let pooled = fused.mean(axis: 1)
        let staticSqueezed = staticFeatures.reshaped([staticFeatures.shape[1]])
        let staticEnhanced = pooled + staticSqueezed

        let mean = outputLayer(staticEnhanced)
        let q10 = quantileLayer10(staticEnhanced)
        let q50 = quantileLayer50(staticEnhanced)
        let q90 = quantileLayer90(staticEnhanced)

        return (mean, q10, q50, q90)
    }
}

public class TemporalFusionTransformer: Module {
    @ModuleInfo var timeEmbedding: TimeEmbedding
    @ModuleInfo var eventEmbedding: EventEmbedding
    @ModuleInfo var staticEmbedding: Linear
    @ModuleInfo var historicalEmbedding: Linear
    @ModuleInfo var futureEmbedding: Linear
    @ModuleInfo var decoder: TemporalFusionDecoder
    @ModuleInfo var gatingLayer: Linear

    internal let dModel: Int
    private let staticSize: Int
    private let historicalSize: Int
    private let futureSize: Int

    public init(
        staticSize: Int = 5,
        historicalSize: Int = 18,
        futureSize: Int = 5,
        dModel: Int = 128,
        numHeads: Int = 8
    ) {
        self.dModel = dModel
        self.staticSize = staticSize
        self.historicalSize = historicalSize
        self.futureSize = futureSize

        self.timeEmbedding = TimeEmbedding(dModel: dModel)
        self.eventEmbedding = EventEmbedding(numEventTypes: 10, dModel: dModel)
        self.staticEmbedding = Linear(staticSize, dModel)
        self.historicalEmbedding = Linear(historicalSize + dModel, dModel)
        self.futureEmbedding = Linear(futureSize + dModel, dModel)
        self.decoder = TemporalFusionDecoder(
            dModel: dModel,
            numHeads: numHeads,
            staticSize: dModel,
            historicalSize: dModel,
            futureSize: dModel
        )
        self.gatingLayer = Linear(dModel, dModel)

        super.init()
    }

    public func callAsFunction(
        staticInputs: MLXArray,
        historicalInputs: MLXArray,
        futureInputs: MLXArray,
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false
    ) -> MLXArray {
        let timeEmb = timeEmbedding(timestamps)
        let _ = eventIds.isEmpty ? MLXArray.zeros([timestamps.count, dModel]) : eventEmbedding(eventIds)

        let staticEmb = staticEmbedding(staticInputs)

        let historicalWithTime = concatenated([historicalInputs, timeEmb], axis: -1)
        let historicalEmb: MLXArray
        if useCheckpointing {
            historicalEmb = checkpoint { self.historicalEmbedding(historicalWithTime) }
        } else {
            historicalEmb = historicalEmbedding(historicalWithTime)
        }

        let futureWithTime = concatenated([futureInputs, timeEmb], axis: -1)
        let futureEmb: MLXArray
        if useCheckpointing {
            futureEmb = checkpoint { self.futureEmbedding(futureWithTime) }
        } else {
            futureEmb = futureEmbedding(futureWithTime)
        }

        let gatedHistorical = gatingLayer(historicalEmb) * sigmoid(gatingLayer(historicalEmb))
        let gatedFuture = gatingLayer(futureEmb) * sigmoid(gatingLayer(futureEmb))

        return decoder(
            staticInputs: staticEmb,
            historicalInputs: gatedHistorical,
            futureInputs: gatedFuture,
            useCheckpointing: useCheckpointing
        )
    }

    public func callAsFunctionMultiHorizon(
        staticInputs: MLXArray,
        historicalInputs: MLXArray,
        futureInputs: MLXArray,
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false,
        encoderCache: EncoderCache? = nil
    ) -> (horizon1h: MLXArray, horizon4h: MLXArray, horizon24h: MLXArray) {
        let staticEmb: MLXArray
        let gatedHistorical: MLXArray
        let gatedFuture: MLXArray

        if let cache = encoderCache {
            staticEmb = cache.staticEmb
            gatedHistorical = cache.gatedHistorical
            gatedFuture = cache.gatedFuture
        } else {
            let timeEmb = timeEmbedding(timestamps)
            let _ = eventIds.isEmpty ? MLXArray.zeros([timestamps.count, dModel]) : eventEmbedding(eventIds)

            staticEmb = staticEmbedding(staticInputs)

            let historicalWithTime = concatenated([historicalInputs, timeEmb], axis: -1)
            let historicalEmb: MLXArray
            if useCheckpointing {
                historicalEmb = checkpoint { self.historicalEmbedding(historicalWithTime) }
            } else {
                historicalEmb = historicalEmbedding(historicalWithTime)
            }

            let futureWithTime = concatenated([futureInputs, timeEmb], axis: -1)
            let futureEmb: MLXArray
            if useCheckpointing {
                futureEmb = checkpoint { self.futureEmbedding(futureWithTime) }
            } else {
                futureEmb = futureEmbedding(futureWithTime)
            }

            gatedHistorical = gatingLayer(historicalEmb) * sigmoid(gatingLayer(historicalEmb))
            gatedFuture = gatingLayer(futureEmb) * sigmoid(gatingLayer(futureEmb))
        }

        return decoder.callAsFunctionMultiHorizon(
            staticInputs: staticEmb,
            historicalInputs: gatedHistorical,
            futureInputs: gatedFuture,
            useCheckpointing: useCheckpointing
        )
    }

    public func encode(
        staticInputs: MLXArray,
        historicalInputs: MLXArray,
        futureInputs: MLXArray,
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false
    ) -> EncoderCache {
        let timeEmb = timeEmbedding(timestamps)
        let _ = eventIds.isEmpty ? MLXArray.zeros([timestamps.count, dModel]) : eventEmbedding(eventIds)

        let staticEmb = staticEmbedding(staticInputs)

        let historicalWithTime = concatenated([historicalInputs, timeEmb], axis: -1)
        let historicalEmb: MLXArray
        if useCheckpointing {
            historicalEmb = checkpoint { self.historicalEmbedding(historicalWithTime) }
        } else {
            historicalEmb = historicalEmbedding(historicalWithTime)
        }

        let futureWithTime = concatenated([futureInputs, timeEmb], axis: -1)
        let futureEmb: MLXArray
        if useCheckpointing {
            futureEmb = checkpoint { self.futureEmbedding(futureWithTime) }
        } else {
            futureEmb = futureEmbedding(futureWithTime)
        }

        let gatedHistorical = gatingLayer(historicalEmb) * sigmoid(gatingLayer(historicalEmb))
        let gatedFuture = gatingLayer(futureEmb) * sigmoid(gatingLayer(futureEmb))

        let staticFeatures = decoder.staticSelector(staticEmb)
        let historicalFeatures = decoder.historicalSelector(gatedHistorical)
        let futureFeatures = decoder.futureSelector(gatedFuture)

        let combined = concatenated([historicalFeatures, futureFeatures], axis: 1)
        let fused: MLXArray
        if useCheckpointing {
            fused = checkpoint { decoder.temporalFusion(combined) }
        } else {
            fused = decoder.temporalFusion(combined)
        }

        let pooled = fused.mean(axis: 1)
        let staticSqueezed = staticFeatures.reshaped([staticFeatures.shape[1]])
        let staticEnhanced = pooled + staticSqueezed

        return EncoderCache(
            staticEmb: staticEmb,
            gatedHistorical: gatedHistorical,
            gatedFuture: gatedFuture,
            staticEnhanced: staticEnhanced
        )
    }
}

public struct EncoderCache {
    public let staticEmb: MLXArray
    public let gatedHistorical: MLXArray
    public let gatedFuture: MLXArray
    public let staticEnhanced: MLXArray

    public init(staticEmb: MLXArray, gatedHistorical: MLXArray, gatedFuture: MLXArray, staticEnhanced: MLXArray) {
        self.staticEmb = staticEmb
        self.gatedHistorical = gatedHistorical
        self.gatedFuture = gatedFuture
        self.staticEnhanced = staticEnhanced
    }
}

public class DynamicLossWeighting {
    private var horizonWeights: [String: Float]
    private var horizonLosses: [String: [Float]]
    private let adaptationRate: Float
    private let minWeight: Float
    private let maxWeight: Float

    public init(initialWeights: [String: Float] = ["1h": 1.0, "4h": 1.0, "24h": 1.0], adaptationRate: Float = 0.1, minWeight: Float = 0.1, maxWeight: Float = 10.0) {
        self.horizonWeights = initialWeights
        self.horizonLosses = [:]
        self.adaptationRate = adaptationRate
        self.minWeight = minWeight
        self.maxWeight = maxWeight
    }

    public func updateWeights(losses: [String: Float]) {
        for (horizon, loss) in losses {
            if horizonLosses[horizon] == nil {
                horizonLosses[horizon] = []
            }
            horizonLosses[horizon]?.append(loss)

            if let currentLosses = horizonLosses[horizon], currentLosses.count > 10 {
                let avgLoss = currentLosses.suffix(10).reduce(0, +) / Float(10)
                let totalAvgLoss = horizonLosses.values.flatMap { $0.suffix(10) }.reduce(0, +) / Float(horizonLosses.count * 10)

                if totalAvgLoss > 0 {
                    let relativeLoss = avgLoss / totalAvgLoss
                    let newWeight = horizonWeights[horizon]! * (1.0 + adaptationRate * (1.0 - relativeLoss))
                    horizonWeights[horizon] = max(minWeight, min(maxWeight, newWeight))
                }
            }
        }
    }

    public func getWeights() -> [String: Float] {
        return horizonWeights
    }

    public func getWeight(horizon: String) -> Float {
        return horizonWeights[horizon] ?? 1.0
    }
}

public class TFTForecaster {
    internal let model: TemporalFusionTransformer
    internal let logger: StructuredLogger
    private var encoderCache: EncoderCache?
    private var cacheKey: String?

    public init(
        staticSize: Int = 5,
        historicalSize: Int = 18,
        futureSize: Int = 5,
        dModel: Int = 128,
        numHeads: Int = 8,
        logger: StructuredLogger
    ) {
        self.model = TemporalFusionTransformer(
            staticSize: staticSize,
            historicalSize: historicalSize,
            futureSize: futureSize,
            dModel: dModel,
            numHeads: numHeads
        )
        self.logger = logger
    }

    public func predict(
        staticFeatures: [[Float]],
        historicalFeatures: [[Float]],
        futureFeatures: [[Float]],
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false
    ) -> [[Float]] {
        let staticArray = MLXArray(staticFeatures.flatMap { $0 }, [staticFeatures.count, staticFeatures[0].count])
        let historicalArray = MLXArray(historicalFeatures.flatMap { $0 }, [historicalFeatures.count, historicalFeatures[0].count])
        let futureArray = MLXArray(futureFeatures.flatMap { $0 }, [futureFeatures.count, futureFeatures[0].count])

        let pred = model(
            staticInputs: staticArray,
            historicalInputs: historicalArray,
            futureInputs: futureArray,
            timestamps: timestamps,
            eventIds: eventIds,
            useCheckpointing: useCheckpointing
        )

        return [pred[0].asArray(Float.self)]
    }

    public func predictMultiHorizon(
        staticFeatures: [[Float]],
        historicalFeatures: [[Float]],
        futureFeatures: [[Float]],
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false,
        useCache: Bool = true
    ) -> (horizon1h: [[Float]], horizon4h: [[Float]], horizon24h: [[Float]]) {
        let staticArray = MLXArray(staticFeatures.flatMap { $0 }, [staticFeatures.count, staticFeatures[0].count])
        let historicalArray = MLXArray(historicalFeatures.flatMap { $0 }, [historicalFeatures.count, historicalFeatures[0].count])
        let futureArray = MLXArray(futureFeatures.flatMap { $0 }, [futureFeatures.count, futureFeatures[0].count])

        let cacheKey = "\(staticFeatures.hashValue)_\(historicalFeatures.hashValue)_\(futureFeatures.hashValue)_\(timestamps.count)"
        let cache: EncoderCache?

        if useCache && self.cacheKey == cacheKey, let existingCache = encoderCache {
            cache = existingCache
            logger.info(component: "TFTForecaster", event: "Using cached encoder outputs")
        } else {
            cache = model.encode(
                staticInputs: staticArray,
                historicalInputs: historicalArray,
                futureInputs: futureArray,
                timestamps: timestamps,
                eventIds: eventIds,
                useCheckpointing: useCheckpointing
            )
            if useCache {
                self.encoderCache = cache
                self.cacheKey = cacheKey
            }
        }

        let (h1h, h4h, h24h) = model.callAsFunctionMultiHorizon(
            staticInputs: staticArray,
            historicalInputs: historicalArray,
            futureInputs: futureArray,
            timestamps: timestamps,
            eventIds: eventIds,
            useCheckpointing: useCheckpointing,
            encoderCache: cache
        )

        return (
            horizon1h: [h1h[0].asArray(Float.self)],
            horizon4h: [h4h[0].asArray(Float.self)],
            horizon24h: [h24h[0].asArray(Float.self)]
        )
    }

    public func clearCache() {
        encoderCache = nil
        cacheKey = nil
        logger.info(component: "TFTForecaster", event: "Encoder cache cleared")
    }

    public func predictQuantiles(
        staticFeatures: [[Float]],
        historicalFeatures: [[Float]],
        futureFeatures: [[Float]],
        timestamps: [Date],
        eventIds: [Int] = [],
        useCheckpointing: Bool = false
    ) -> (mean: [[Float]], quantile10: [[Float]], quantile50: [[Float]], quantile90: [[Float]]) {
        let staticArray = MLXArray(staticFeatures.flatMap { $0 }, [staticFeatures.count, staticFeatures[0].count])
        let historicalArray = MLXArray(historicalFeatures.flatMap { $0 }, [historicalFeatures.count, historicalFeatures[0].count])
        let futureArray = MLXArray(futureFeatures.flatMap { $0 }, [futureFeatures.count, futureFeatures[0].count])

        let timeEmb = model.timeEmbedding(timestamps)
        let _ = eventIds.isEmpty ? MLXArray.zeros([timestamps.count, model.dModel]) : model.eventEmbedding(eventIds)

        let staticEmb = model.staticEmbedding(staticArray)
        let historicalWithTime = concatenated([historicalArray, timeEmb], axis: -1)
        let historicalEmb = model.historicalEmbedding(historicalWithTime)
        let futureWithTime = concatenated([futureArray, timeEmb], axis: -1)
        let futureEmb = model.futureEmbedding(futureWithTime)

        let gatedHistorical = model.gatingLayer(historicalEmb) * sigmoid(model.gatingLayer(historicalEmb))
        let gatedFuture = model.gatingLayer(futureEmb) * sigmoid(model.gatingLayer(futureEmb))

        let (mean, q10, q50, q90) = model.decoder.callAsFunctionWithQuantiles(
            staticInputs: staticEmb,
            historicalInputs: gatedHistorical,
            futureInputs: gatedFuture,
            useCheckpointing: useCheckpointing
        )

        return (
            mean: [mean[0].asArray(Float.self)],
            quantile10: [q10[0].asArray(Float.self)],
            quantile50: [q50[0].asArray(Float.self)],
            quantile90: [q90[0].asArray(Float.self)]
        )
    }
}
