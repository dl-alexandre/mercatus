import Foundation
import MLX
import MLXNN
import MLXOptimizers
import Utils

public struct MultiHorizonTrainingResult {
    public let epoch: Int
    public let totalLoss: Float
    public let horizonLosses: [String: Float]
    public let horizonWeights: [String: Float]
    public let valLoss: Float?
    public let valHorizonLosses: [String: Float]?
}

public extension TFTForecaster {
    func trainMultiHorizon(
        staticFeatures: [[Float]],
        historicalFeatures: [[Float]],
        futureFeatures: [[Float]],
        targets1h: [[Float]],
        targets4h: [[Float]],
        targets24h: [[Float]],
        timestamps: [Date],
        eventIds: [Int] = [],
        epochs: Int = 100,
        learningRate: Float = 1e-3,
        validationSplit: Double = 0.2,
        useCheckpointing: Bool = false,
        dynamicWeighting: Bool = true,
        initialWeights: [String: Float] = ["1h": 1.0, "4h": 1.0, "24h": 1.0],
        adaptationRate: Float = 0.1
    ) async throws -> [MultiHorizonTrainingResult] {
        logger.info(component: "TFTForecaster", event: "Starting multi-horizon training", data: [
            "epochs": String(epochs),
            "samples": String(staticFeatures.count),
            "dynamicWeighting": String(dynamicWeighting)
        ])

        guard staticFeatures.count == historicalFeatures.count &&
              staticFeatures.count == futureFeatures.count &&
              staticFeatures.count == targets1h.count &&
              staticFeatures.count == targets4h.count &&
              staticFeatures.count == targets24h.count else {
            throw MLXError.invalidInput
        }

        let staticArray = MLXArray(staticFeatures.flatMap { $0 }, [staticFeatures.count, staticFeatures[0].count]).asType(Float.self)
        let historicalArray = MLXArray(historicalFeatures.flatMap { $0 }, [historicalFeatures.count, historicalFeatures[0].count]).asType(Float.self)
        let futureArray = MLXArray(futureFeatures.flatMap { $0 }, [futureFeatures.count, futureFeatures[0].count]).asType(Float.self)

        let targets1hArray = MLXArray(targets1h.flatMap { $0 }, [targets1h.count, targets1h[0].count]).asType(Float.self)
        let targets4hArray = MLXArray(targets4h.flatMap { $0 }, [targets4h.count, targets4h[0].count]).asType(Float.self)
        let targets24hArray = MLXArray(targets24h.flatMap { $0 }, [targets24h.count, targets24h[0].count]).asType(Float.self)

        let splitIdx = Int(Double(staticFeatures.count) * (1.0 - validationSplit))
        let trainStatic = staticArray[0..<splitIdx]
        let trainHistorical = historicalArray[0..<splitIdx]
        let trainFuture = futureArray[0..<splitIdx]
        let trainTargets1h = targets1hArray[0..<splitIdx]
        let trainTargets4h = targets4hArray[0..<splitIdx]
        let trainTargets24h = targets24hArray[0..<splitIdx]
        let trainTimestamps = Array(timestamps[0..<splitIdx])
        let trainEventIds = eventIds.isEmpty ? [] : Array(eventIds[0..<splitIdx])

        let valStatic = staticArray[splitIdx..<staticFeatures.count]
        let valHistorical = historicalArray[splitIdx..<historicalFeatures.count]
        let valFuture = futureArray[splitIdx..<futureFeatures.count]
        let valTargets1h = targets1hArray[splitIdx..<targets1h.count]
        let valTargets4h = targets4hArray[splitIdx..<targets4h.count]
        let valTargets24h = targets24hArray[splitIdx..<targets24h.count]
        let valTimestamps = Array(timestamps[splitIdx..<timestamps.count])
        let valEventIds = eventIds.isEmpty ? [] : Array(eventIds[splitIdx..<eventIds.count])

        let optimizer = AdamW(learningRate: learningRate, weightDecay: 1e-4)
        let lossWeighting = DynamicLossWeighting(initialWeights: initialWeights, adaptationRate: adaptationRate)

        func multiHorizonLoss(
            model: TemporalFusionTransformer,
            staticInputs: MLXArray,
            historicalInputs: MLXArray,
            futureInputs: MLXArray,
            timestamps: [Date],
            eventIds: [Int],
            targets1h: MLXArray,
            targets4h: MLXArray,
            targets24h: MLXArray,
            weights: [String: Float],
            useCheckpointing: Bool
        ) -> (total: MLXArray, losses: [String: MLXArray]) {
            let (pred1h, pred4h, pred24h) = model.callAsFunctionMultiHorizon(
                staticInputs: staticInputs,
                historicalInputs: historicalInputs,
                futureInputs: futureInputs,
                timestamps: timestamps,
                eventIds: eventIds,
                useCheckpointing: useCheckpointing
            )

            let diff1h = pred1h - targets1h
            let diff4h = pred4h - targets4h
            let diff24h = pred24h - targets24h

            let loss1h = (diff1h * diff1h).mean() * MLXArray(weights["1h"] ?? 1.0)
            let loss4h = (diff4h * diff4h).mean() * MLXArray(weights["4h"] ?? 1.0)
            let loss24h = (diff24h * diff24h).mean() * MLXArray(weights["24h"] ?? 1.0)

            let totalLoss = loss1h + loss4h + loss24h

            return (totalLoss, [
                "1h": (diff1h * diff1h).mean(),
                "4h": (diff4h * diff4h).mean(),
                "24h": (diff24h * diff24h).mean()
            ])
        }

        var results: [MultiHorizonTrainingResult] = []

        for epoch in 0..<epochs {
            let weights = lossWeighting.getWeights()

            func lossWrapper(model: TemporalFusionTransformer, _: MLXArray, _: MLXArray) -> MLXArray {
                let (total, _) = multiHorizonLoss(
                    model: model,
                    staticInputs: trainStatic,
                    historicalInputs: trainHistorical,
                    futureInputs: trainFuture,
                    timestamps: trainTimestamps,
                    eventIds: trainEventIds,
                    targets1h: trainTargets1h,
                    targets4h: trainTargets4h,
                    targets24h: trainTargets24h,
                    weights: weights,
                    useCheckpointing: useCheckpointing
                )
                return total
            }

            let lg = valueAndGrad(model: model, lossWrapper)
            let dummyArray = MLXArray([Float(0.0)])
            let (lossValue, grads) = lg(model, dummyArray, dummyArray)

            optimizer.update(model: model, gradients: grads)

            let (_, trainLosses) = multiHorizonLoss(
                model: model,
                staticInputs: trainStatic,
                historicalInputs: trainHistorical,
                futureInputs: trainFuture,
                timestamps: trainTimestamps,
                eventIds: trainEventIds,
                targets1h: trainTargets1h,
                targets4h: trainTargets4h,
                targets24h: trainTargets24h,
                weights: weights,
                useCheckpointing: useCheckpointing
            )

            var trainLossDict: [String: Float] = [:]
            for (horizon, lossArray) in trainLosses {
                trainLossDict[horizon] = lossArray.item(Float.self)
            }

            if dynamicWeighting {
                lossWeighting.updateWeights(losses: trainLossDict)
            }

            var valLossDict: [String: Float]? = nil
            var valTotalLoss: Float? = nil

            if validationSplit > 0 {
                let (valTotal, valLosses) = multiHorizonLoss(
                    model: model,
                    staticInputs: valStatic,
                    historicalInputs: valHistorical,
                    futureInputs: valFuture,
                    timestamps: valTimestamps,
                    eventIds: valEventIds,
                    targets1h: valTargets1h,
                    targets4h: valTargets4h,
                    targets24h: valTargets24h,
                    weights: ["1h": 1.0, "4h": 1.0, "24h": 1.0],
                    useCheckpointing: useCheckpointing
                )

                valTotalLoss = valTotal.item(Float.self)
                valLossDict = [:]
                for (horizon, lossArray) in valLosses {
                    valLossDict![horizon] = lossArray.item(Float.self)
                }
            }

            let result = MultiHorizonTrainingResult(
                epoch: epoch,
                totalLoss: lossValue.item(Float.self),
                horizonLosses: trainLossDict,
                horizonWeights: lossWeighting.getWeights(),
                valLoss: valTotalLoss,
                valHorizonLosses: valLossDict
            )
            results.append(result)

            if epoch % 10 == 0 {
                let loss1h = trainLossDict["1h"] ?? 0
                let loss4h = trainLossDict["4h"] ?? 0
                let loss24h = trainLossDict["24h"] ?? 0
                let weight1h = weights["1h"] ?? 1.0
                let weight4h = weights["4h"] ?? 1.0
                let weight24h = weights["24h"] ?? 1.0

                logger.info(component: "TFTForecaster", event: "Training progress", data: [
                    "epoch": String(epoch),
                    "totalLoss": String(result.totalLoss),
                    "loss1h": String(loss1h),
                    "loss4h": String(loss4h),
                    "loss24h": String(loss24h),
                    "weight1h": String(weight1h),
                    "weight4h": String(weight4h),
                    "weight24h": String(weight24h)
                ])
            }
        }

        logger.info(component: "TFTForecaster", event: "Multi-horizon training completed")
        return results
    }
}
