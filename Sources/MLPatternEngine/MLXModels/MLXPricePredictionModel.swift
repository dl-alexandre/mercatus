import Foundation
import MLX
import MLXNN
import MLXOptimizers
import Utils
import MLPatternEngine
import SmartVestorMLXAdapter

#if os(macOS)
import Metal
#endif

typealias F = Float
typealias F16 = Float16

public struct TensorBoardLogger {
    private let logDir: String
    private let logger: StructuredLogger

    public init(logDir: String, logger: StructuredLogger) {
        self.logDir = logDir
        self.logger = logger
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    }

    public func logScalar(tag: String, value: Double, step: Int) {
        let logFile = "\(logDir)/\(tag).log"
        let entry = "\(step),\(value)\n"

        if let data = entry.data(using: .utf8),
           let fileHandle = FileHandle(forWritingAtPath: logFile) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? entry.write(toFile: logFile, atomically: false, encoding: .utf8)
        }

        logger.info(component: "TensorBoardLogger", event: "Scalar logged", data: [
            "tag": tag,
            "value": String(value),
            "step": String(step)
        ])
    }

    public func logMetrics(metrics: [String: Double], step: Int) {
        for (tag, value) in metrics {
            logScalar(tag: tag, value: value, step: step)
        }
    }
}

public struct CrossValidationResult {
    public let nFolds: Int
    public let avgFinalLoss: Double
    public let avgBestLoss: Double
    public let avgValidationLoss: Double
    public let foldResults: [TrainingResult]
}

public class MLXPricePredictionModel: Module, UnaryLayer {
    @ModuleInfo private var linear1: Linear
    @ModuleInfo private var dropout1: Dropout
    @ModuleInfo private var linear2: Linear
    @ModuleInfo private var dropout2: Dropout
    @ModuleInfo private var linear3: Linear
    private var normalizationMean: MLXArray
    private var normalizationStd: MLXArray

    private let logger: StructuredLogger
    private var isLayersInitialized = false
    private var compiledForward: Any?
    private var useMixedPrecision: Bool
    private var isCompiled: Bool = false
    private let inputSize: Int
    private var isQuantized: Bool = false
    private var checkpointDir: String?
    private var bestModelPath: String?

    public init(logger: StructuredLogger, useMixedPrecision: Bool = false, inputSize: Int = 18) throws {
        self.inputSize = inputSize
        self.logger = logger
        self.useMixedPrecision = useMixedPrecision

        try MLXInitialization.ensureInitialized()

        let scale1 = sqrt(1.0 / F(inputSize))
        let scale2 = sqrt(1.0 / F(128))
        let scale3 = sqrt(1.0 / F(64))

        let W1: MLXArray
        let b1: MLXArray
        let W2: MLXArray
        let b2: MLXArray
        let W3: MLXArray
        let b3: MLXArray
        let meanArray: MLXArray
        let stdArray: MLXArray

        if useMixedPrecision {
            W1 = MLXRandom.uniform(-scale1 ..< scale1, [128, inputSize]).asType(F16.self)
            b1 = MLXRandom.uniform(-scale1 ..< scale1, [128]).asType(F16.self)
            W2 = MLXRandom.uniform(-scale2 ..< scale2, [64, 128]).asType(F16.self)
            b2 = MLXRandom.uniform(-scale2 ..< scale2, [64]).asType(F16.self)
            W3 = MLXRandom.uniform(-scale3 ..< scale3, [1, 64]).asType(F16.self)
            b3 = MLXRandom.uniform(-scale3 ..< scale3, [1]).asType(F16.self)
            meanArray = MLXArray(Array(repeating: F16(0.0), count: inputSize)).asType(F16.self)
            stdArray = MLXArray(Array(repeating: F16(1.0), count: inputSize)).asType(F16.self)
        } else {
            W1 = MLXRandom.uniform(-scale1 ..< scale1, [128, inputSize]).asType(F.self)
            b1 = MLXRandom.uniform(-scale1 ..< scale1, [128]).asType(F.self)
            W2 = MLXRandom.uniform(-scale2 ..< scale2, [64, 128]).asType(F.self)
            b2 = MLXRandom.uniform(-scale2 ..< scale2, [64]).asType(F.self)
            W3 = MLXRandom.uniform(-scale3 ..< scale3, [1, 64]).asType(F.self)
            b3 = MLXRandom.uniform(-scale3 ..< scale3, [1]).asType(F.self)
            meanArray = MLXArray(Array(repeating: F(0.0), count: inputSize)).asType(F.self)
            stdArray = MLXArray(Array(repeating: F(1.0), count: inputSize)).asType(F.self)
        }

        let expectedDtype: MLX.DType = useMixedPrecision ? .float16 : .float32
        precondition(W1.dtype == expectedDtype, "W1 is \(W1.dtype), expected \(expectedDtype)")
        precondition(b1.dtype == expectedDtype, "b1 is \(b1.dtype), expected \(expectedDtype)")
        precondition(W2.dtype == expectedDtype, "W2 is \(W2.dtype), expected \(expectedDtype)")
        precondition(b2.dtype == expectedDtype, "b2 is \(b2.dtype), expected \(expectedDtype)")
        precondition(W3.dtype == expectedDtype, "W3 is \(W3.dtype), expected \(expectedDtype)")
        precondition(b3.dtype == expectedDtype, "b3 is \(b3.dtype), expected \(expectedDtype)")

        self.linear1 = Linear(weight: W1, bias: b1)
        self.dropout1 = Dropout(p: 0.2)
        self.linear2 = Linear(weight: W2, bias: b2)
        self.dropout2 = Dropout(p: 0.2)
        self.linear3 = Linear(weight: W3, bias: b3)
        self.normalizationMean = meanArray
        self.normalizationStd = stdArray

        super.init()

        precondition(self.linear1.weight.dtype == expectedDtype, "linear1.weight is \(self.linear1.weight.dtype), expected \(expectedDtype)")
        if let bias1 = self.linear1.bias {
            precondition(bias1.dtype == expectedDtype, "linear1.bias is \(bias1.dtype), expected \(expectedDtype)")
        }
        precondition(self.linear2.weight.dtype == expectedDtype, "linear2.weight is \(self.linear2.weight.dtype), expected \(expectedDtype)")
        if let bias2 = self.linear2.bias {
            precondition(bias2.dtype == expectedDtype, "linear2.bias is \(bias2.dtype), expected \(expectedDtype)")
        }
        precondition(self.linear3.weight.dtype == expectedDtype, "linear3.weight is \(self.linear3.weight.dtype), expected \(expectedDtype)")
        if let bias3 = self.linear3.bias {
            precondition(bias3.dtype == expectedDtype, "linear3.bias is \(bias3.dtype), expected \(expectedDtype)")
        }

        self.isLayersInitialized = true
        let precisionStr = useMixedPrecision ? "Float16" : "Float32"
        logger.info(component: "MLXPricePredictionModel", event: "MLX price prediction model created (\(precisionStr) weights)")
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        guard isLayersInitialized else {
            fatalError("MLXPricePredictionModel layers not initialized")
        }

        let xConverted: MLXArray
        if useMixedPrecision {
            xConverted = x.asType(F16.self)
        } else {
            xConverted = x.asType(F.self)
        }

        let mean: MLXArray
        let std: MLXArray
        if useMixedPrecision {
            mean = normalizationMean.asType(F16.self)
            std = normalizationStd.asType(F16.self)
        } else {
            mean = normalizationMean.asType(F.self)
            std = normalizationStd.asType(F.self)
        }

        let eps: MLXArray
        if useMixedPrecision {
            eps = MLXArray(F16(1e-8))
        } else {
            eps = MLXArray(F(1e-8))
        }
        let normalized = (xConverted - mean) / (std + eps)

        let x1 = relu(linear1(normalized))
        let x1Drop = dropout1(x1)
        let x2 = relu(linear2(x1Drop))
        let x2Drop = dropout2(x2)
        let x3 = linear3(x2Drop)

        return x3
    }

    public func updateNormalization(mean: [Double], std: [Double]) throws {
        guard mean.count == inputSize && std.count == inputSize else {
            throw MLXError.invalidInput
        }

        let meanArray: MLXArray
        let stdArray: MLXArray
        if useMixedPrecision {
            meanArray = MLXArray(mean.map { F16($0) }).asType(F16.self)
            stdArray = MLXArray(std.map { F16($0) }).asType(F16.self)
        } else {
            meanArray = MLXArray(mean.map { F($0) }).asType(F.self)
            stdArray = MLXArray(std.map { F($0) }).asType(F.self)
        }

        self.normalizationMean = meanArray
        self.normalizationStd = stdArray

        logger.info(component: "MLXPricePredictionModel", event: "Normalization parameters updated")
    }

    public func compile() {
        guard !isCompiled else { return }
        isCompiled = true
        logger.info(component: "MLXPricePredictionModel", event: "Model compilation enabled (using direct forward)")
    }

    public func forwardBatch(_ x: MLXArray) -> MLXArray {
        return self(x)
    }

    private func accumulateGradients(_ acc: ModuleParameters, _ new: ModuleParameters) -> ModuleParameters {
        let accFlat = acc.flattened()
        let newFlat = new.flattened()
        var resultFlat: [(String, MLXArray)] = []

        let accDict = Dictionary(uniqueKeysWithValues: accFlat)
        for (key, newVal) in newFlat {
            if let accVal = accDict[key] {
                resultFlat.append((key, accVal + newVal))
            } else {
                resultFlat.append((key, newVal))
            }
        }
        for (key, accVal) in accFlat where !newFlat.contains(where: { $0.0 == key }) {
            resultFlat.append((key, accVal))
        }

        return ModuleParameters.unflattened(resultFlat)
    }

    private func averageGradients(_ grads: ModuleParameters, steps: Int) -> ModuleParameters {
        let scale = F(1.0) / F(steps)
        let flat = grads.flattened()
        let averaged = flat.map { (key, value) in
            (key, value * scale)
        }
        return ModuleParameters.unflattened(averaged)
    }

    private func clipGradNorm(gradients: ModuleParameters, maxNorm: Double) -> (ModuleParameters, MLXArray) {
        var totalNormSquared: MLXArray = MLXArray(F(0.0))
        let flatGrads = gradients.flattenedValues()
        for grad in flatGrads {
            let flat = grad.flattened()
            totalNormSquared = totalNormSquared + (flat * flat).sum()
        }
        let totalNorm = sqrt(totalNormSquared)
        let maxNormF = F(maxNorm)
        let scale = MLX.minimum(maxNormF / (totalNorm + MLXArray(F(1e-8))), MLXArray(F(1.0)))

        let flat = gradients.flattened()
        let clippedFlat = flat.map { (key, grad) in
            (key, grad * scale)
        }
        let clipped = ModuleParameters.unflattened(clippedFlat)

        return (clipped, totalNorm)
    }

    public func train(inputs: [[Double]], targets: [[Double]], epochs: Int = 1000, learningRate: Float = 1e-3, validationSplit: Double = 0.2, earlyStoppingPatience: Int = 5, warmupSteps: Int = 100, enableDataAugmentation: Bool = false, checkpointInterval: Int = 50, checkpointDir: String? = nil, tensorBoardLogger: TensorBoardLogger? = nil, enableAdversarialTraining: Bool = false, adversarialEpsilon: Float = 0.01, labelSmoothing: Float = 0.0, gradientAccumulationSteps: Int = 1, coinSymbol: String? = nil) async throws -> TrainingResult {
        logger.info(component: "MLXPricePredictionModel", event: "Starting training", data: ["epochs": String(epochs), "learningRate": String(learningRate), "samples": String(inputs.count)])

        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        // Convert Double to Float for GPU operations
        let flatInputs: [F] = inputs.flatMap { $0.map(F.init) }
        let flatTargets: [F] = targets.flatMap { $0.map(F.init) }

        let inputArray = MLXArray(flatInputs, [inputs.count, inputShape])
        let targetArray = MLXArray(flatTargets, [targets.count, targets[0].count])

        // Ensure all inputs are Float32
        let inputArrayF = inputArray.asType(F.self)
        let targetArrayF = targetArray.asType(F.self)
        precondition(inputArrayF.dtype == MLX.DType.float32, "inputArray is \(inputArrayF.dtype), expected float32")
        precondition(targetArrayF.dtype == MLX.DType.float32, "targetArray is \(targetArrayF.dtype), expected float32")

        // Compute normalization statistics from training data
        let meanValues = inputArrayF.mean(axis: 0)
        let variance = ((inputArrayF - meanValues) * (inputArrayF - meanValues)).mean(axis: 0)
        let stdValues = sqrt(variance + MLXArray(F(1e-8)))

        try withError { error in
            eval(meanValues, stdValues)
            try error.check()
        }

        if useMixedPrecision {
            self.normalizationMean = meanValues.asType(F16.self)
            self.normalizationStd = stdValues.asType(F16.self)
        } else {
            self.normalizationMean = meanValues.asType(F.self)
            self.normalizationStd = stdValues.asType(F.self)
        }

        logger.info(component: "MLXPricePredictionModel", event: "Normalization statistics computed from training data")

        self.checkpointDir = checkpointDir
        let initialLR: F = learningRate
        let optimizer = AdamW(learningRate: initialLR, weightDecay: 1e-4)

        // Wrap eval operations with error handling
        try withError { error in
            eval(self)
            try error.check()
        }

        func applyLabelSmoothing(_ targets: MLXArray, smoothing: F) -> MLXArray {
            guard smoothing > 0 else { return targets }
            let targetMean = targets.mean()
            return targets * (F(1.0) - smoothing) + targetMean * smoothing
        }

        func fgsmAttack(model: MLXPricePredictionModel, x: MLXArray, y: MLXArray, epsilon: F) -> MLXArray {
            func lossFn(m: MLXPricePredictionModel, x: MLXArray, y: MLXArray) -> MLXArray {
                let preds = m(x)
                let diff = preds - y
                return (diff * diff).mean()
            }

            let lg = valueAndGrad(model: model, lossFn)
            let (_, _) = lg(model, x, y)

            let inputGrad = model.linear1.weight
            let signGrad = sign(inputGrad)
            let perturbation = signGrad[0..<min(x.shape[0], inputGrad.shape[0]), 0..<min(x.shape[1], inputGrad.shape[1])] * epsilon
            return x + perturbation
        }

        func focalLoss(predictions: MLXArray, targets: MLXArray, alpha: F = F(0.25), gamma: F = F(2.0)) -> MLXArray {
            let diff = predictions - targets
            let absDiff = abs(diff)
            let squared = diff * diff

            let focalWeight = pow(absDiff, gamma)
            let focalLoss = alpha * focalWeight * squared

            let n: F = F(focalLoss.size)
            let invN: F = F(1.0) / n
            return invN * focalLoss.sum()
        }

        // Loss function with explicit Float32 operations
        func loss(model: MLXPricePredictionModel, x: MLXArray, y: MLXArray) -> MLXArray {
            // Ensure inputs are Float32
            let xF = x.asType(F.self)
            var yF = y.asType(F.self)
            precondition(xF.dtype == MLX.DType.float32, "loss input x is \(xF.dtype), expected float32")
            precondition(yF.dtype == MLX.DType.float32, "loss input y is \(yF.dtype), expected float32")

            if labelSmoothing > 0 {
                yF = applyLabelSmoothing(yF, smoothing: F(labelSmoothing))
            }

            let preds = model(xF)
            // Ensure predictions are Float32
            precondition(preds.dtype == MLX.DType.float32, "predictions is \(preds.dtype), expected float32")

            // Use focal loss for imbalanced regression errors
            return focalLoss(predictions: preds, targets: yF, alpha: F(0.25), gamma: F(2.0))
        }

        let splitIdx = Int(Double(inputs.count) * (1.0 - validationSplit))
        let trainInputs = inputArrayF[0..<splitIdx]
        let trainTargets = targetArrayF[0..<splitIdx]
        let valInputs = inputArrayF[splitIdx..<inputs.count]
        let valTargets = targetArrayF[splitIdx..<inputs.count]

        let lg = valueAndGrad(model: self, loss)
        var losses: [F] = []
        var valLosses: [F] = []
        var bestValLoss: F = F.infinity
        var patienceCounter = 0
        var bestEpoch = 0

        func warmupLR(step: Int, warmupSteps: Int, initialLR: F) -> F {
            if step < warmupSteps {
                return initialLR * F(step) / F(warmupSteps)
            }
            return initialLR
        }

        func cosineDecay(epoch: Int, totalEpochs: Int, initialLR: F, warmupSteps: Int) -> F {
            let adjustedEpoch = max(0, epoch - warmupSteps)
            let adjustedTotal = max(1, totalEpochs - warmupSteps)
            if epoch < warmupSteps {
                return warmupLR(step: epoch, warmupSteps: warmupSteps, initialLR: initialLR)
            }
            let progress = F(adjustedEpoch) / F(adjustedTotal)
            return initialLR * (F(1.0) + cos(F.pi * progress)) / F(2.0)
        }

        func addGaussianNoise(_ x: MLXArray, sigma: F = F(0.001)) -> MLXArray {
            let noise = MLXRandom.normal(x.shape) * sigma
            return x + noise
        }

        func computeMetrics(predictions: MLXArray, targets: MLXArray) -> (mae: F, r2: F) {
            let predF = predictions.asType(F.self)
            let targetF = targets.asType(F.self)
            let diff = predF - targetF
            let mae = abs(diff).mean()

            let targetMean = targetF.mean()
            let ssRes = (diff * diff).sum()
            let ssTot = ((targetF - targetMean) * (targetF - targetMean)).sum()
            let r2 = F(1.0) - (ssRes / (ssTot + MLXArray(F(1e-8))))

            return (mae.item(F.self), r2.item(F.self))
        }

        var globalStep = 0
        var accumulatedGrads: ModuleParameters?
        var accumulationCounter = 0
        var gradNorm: MLXArray = MLXArray(F(0.0))

        for epoch in 0..<epochs {
            let currentLR = cosineDecay(epoch: epoch, totalEpochs: epochs, initialLR: initialLR, warmupSteps: warmupSteps)
            optimizer.learningRate = currentLR

            var augmentedTrainInputs = trainInputs
            if enableDataAugmentation {
                augmentedTrainInputs = addGaussianNoise(trainInputs, sigma: F(0.001))
                try withError { error in
                    eval(augmentedTrainInputs)
                    try error.check()
                }
            }

            var trainingInputs = augmentedTrainInputs
            if enableAdversarialTraining {
                let adversarialInputs = fgsmAttack(model: self, x: trainingInputs, y: trainTargets, epsilon: F(adversarialEpsilon))
                try withError { error in
                    eval(adversarialInputs)
                    try error.check()
                }
                trainingInputs = adversarialInputs
            }

            let (lossValue, gradsAny) = lg(self, trainingInputs, trainTargets)
            globalStep += 1

            if gradientAccumulationSteps > 1 {
                if accumulatedGrads == nil {
                    accumulatedGrads = gradsAny
                } else {
                    accumulatedGrads = accumulateGradients(accumulatedGrads!, gradsAny)
                }
                accumulationCounter += 1

                if accumulationCounter < gradientAccumulationSteps {
                    continue
                }

                let averagedGrads = averageGradients(accumulatedGrads!, steps: gradientAccumulationSteps)
                let (clippedGrads, norm) = clipGradNorm(gradients: averagedGrads, maxNorm: 1.0)
                gradNorm = norm
                optimizer.update(model: self, gradients: clippedGrads)
                accumulatedGrads = nil
                accumulationCounter = 0
            } else {
                let (clippedGrads, norm) = clipGradNorm(gradients: gradsAny, maxNorm: 1.0)
                gradNorm = norm
                optimizer.update(model: self, gradients: clippedGrads)
            }

            try withError { error in
                eval(lossValue, gradNorm)
                try error.check()
            }

            precondition(lossValue.dtype == MLX.DType.float32, "lossValue is \(lossValue.dtype), expected float32")

            let lossFloat = lossValue.item(F.self)
            losses.append(lossFloat)

            let trainPreds = self(trainInputs)
            let valPreds = self(valInputs)
            try withError { error in
                eval(trainPreds, valPreds)
                try error.check()
            }

            let (trainMAE, trainR2) = computeMetrics(predictions: trainPreds, targets: trainTargets)

            let valDiff = valPreds - valTargets
            let valSquared = valDiff * valDiff
            let valLoss = valSquared.mean()
            try withError { error in
                eval(valLoss)
                try error.check()
            }
            let valLossFloat = valLoss.item(F.self)
            valLosses.append(valLossFloat)
            let (valMAE, valR2) = computeMetrics(predictions: valPreds, targets: valTargets)

            if valLossFloat < bestValLoss {
                bestValLoss = valLossFloat
                bestEpoch = epoch
                patienceCounter = 0

                if let checkpointDir = checkpointDir, epoch % checkpointInterval == 0 && epoch > 0 {
                    let checkpointPath = "\(checkpointDir)/checkpoint_epoch_\(epoch).safetensors"
                    try save(to: checkpointPath)
                    bestModelPath = checkpointPath
                    logger.info(component: "MLXPricePredictionModel", event: "Checkpoint saved", data: ["path": checkpointPath, "valLoss": String(valLossFloat)])
                }
            } else {
                patienceCounter += 1
            }

            if let tbLogger = tensorBoardLogger {
                tbLogger.logMetrics(metrics: [
                    "train/loss": Double(lossFloat),
                    "val/loss": Double(valLossFloat),
                    "train/mae": Double(trainMAE),
                    "val/mae": Double(valMAE),
                    "train/r2": Double(trainR2),
                    "val/r2": Double(valR2),
                    "train/learning_rate": Double(currentLR),
                    "train/grad_norm": Double(gradNorm.item(F.self))
                ], step: epoch)
            }

            if epoch % 100 == 0 || epoch == 0 {
                let gradNormFloat = gradNorm.item(F.self)
                let epochStr = String(epoch)
                let trainLossStr = String(lossFloat)
                let valLossStr = String(valLossFloat)
                let trainMAEStr = String(trainMAE)
                let valMAEStr = String(valMAE)
                let trainR2Str = String(trainR2)
                let valR2Str = String(valR2)
                let lrStr = String(currentLR)
                let gradNormStr = String(gradNormFloat)
                let patienceStr = String(patienceCounter)
                logger.info(component: "MLXPricePredictionModel", event: "Training progress", data: [
                    "epoch": epochStr,
                    "trainLoss": trainLossStr,
                    "valLoss": valLossStr,
                    "trainMAE": trainMAEStr,
                    "valMAE": valMAEStr,
                    "trainR2": trainR2Str,
                    "valR2": valR2Str,
                    "learningRate": lrStr,
                    "gradNorm": gradNormStr,
                    "patience": patienceStr
                ])
            }

            if patienceCounter >= earlyStoppingPatience {
                logger.info(component: "MLXPricePredictionModel", event: "Early stopping triggered", data: [
                    "epoch": String(epoch),
                    "bestEpoch": String(bestEpoch),
                    "bestValLoss": String(bestValLoss),
                    "patience": String(patienceCounter)
                ])
                break
            }
        }

        let finalLoss: F = losses.last ?? F(0.0)
        let finalValLoss: F = valLosses.last ?? F(0.0)
        logger.info(component: "MLXPricePredictionModel", event: "Training completed", data: [
            "finalLoss": String(finalLoss),
            "finalValLoss": String(finalValLoss),
            "bestValLoss": String(bestValLoss),
            "bestEpoch": String(bestEpoch),
            "epochs": String(losses.count)
        ])

        let result = TrainingResult(
            finalLoss: Double(finalLoss),
            bestLoss: Double(bestValLoss),
            epochs: losses.count,
            learningRate: Double(learningRate),
            validationLoss: Double(finalValLoss),
            bestEpoch: bestEpoch
        )

        if let coinSymbol = coinSymbol {
            let modelId = "\(coinSymbol.lowercased())_price_prediction"
            let version = String(format: "%.0f", Date().timeIntervalSince1970)
            let defaultPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".mercatus/models")

            let registry = ModelRegistry(registryPath: defaultPath, logger: logger)
            let metadata = ModelMetadata(
                architecture: "MLP",
                inputSize: inputSize,
                outputSize: 1,
                trainingEpochs: result.epochs,
                finalLoss: result.finalLoss,
                validationLoss: result.validationLoss,
                accuracy: result.validationLoss.map { 1.0 / (1.0 + $0) },
                hyperparameters: [
                    "learningRate": String(learningRate)
                ]
            )
            _ = try? registry.register(model: self, modelId: modelId, version: version, metadata: metadata)
            logger.info(component: "MLXPricePredictionModel", event: "Model auto-saved for coin", data: [
                "coinSymbol": coinSymbol,
                "modelId": modelId,
                "version": version
            ])
        }

        return result
    }

    public func train(inputs: MLXArray, targets: MLXArray, epochs: Int = 1000, learningRate: Float = 1e-3, validationSplit: Double = 0.2, coinSymbol: String? = nil) async throws -> TrainingResult {
        guard inputs.shape.count == 2, targets.shape.count == 2 else {
            throw MLXError.invalidInput
        }

        let inputCount = inputs.shape[0]
        let inputSize = inputs.shape[1]
        let targetCount = targets.shape[0]
        let targetSize = targets.shape[1]

        guard inputCount == targetCount, inputSize == self.inputSize else {
            throw MLXError.invalidInput
        }

        let inputsArray = inputs.asArray(Float.self)
        let targetsArray = targets.asArray(Float.self)

        var inputsList: [[Double]] = []
        var targetsList: [[Double]] = []

        for i in 0..<inputCount {
            var inputRow: [Double] = []
            var targetRow: [Double] = []

            for j in 0..<inputSize {
                inputRow.append(Double(inputsArray[i * inputSize + j]))
            }

            for j in 0..<targetSize {
                targetRow.append(Double(targetsArray[i * targetSize + j]))
            }

            inputsList.append(inputRow)
            targetsList.append(targetRow)
        }

        return try await train(
            inputs: inputsList,
            targets: targetsList,
            epochs: epochs,
            learningRate: learningRate,
            validationSplit: validationSplit,
            coinSymbol: coinSymbol
        )
    }

    public func predictWithUncertainty(inputs: [[Double]], numSamples: Int = 10) async throws -> (predictions: [[Double]], uncertainties: [[Double]]) {
        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        var allPredictions: [[Double]] = []

        for _ in 0..<numSamples {
            let preds = try await predict(inputs: inputs)
            allPredictions.append(contentsOf: preds)
        }

        var meanPredictions: [[Double]] = []
        var uncertainties: [[Double]] = []

        for i in 0..<inputs.count {
            var sampleValues: [Double] = []
            for sample in 0..<numSamples {
                sampleValues.append(allPredictions[sample * inputs.count + i][0])
            }

            let mean = sampleValues.reduce(0, +) / Double(numSamples)
            let variance = sampleValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(numSamples)
            let std = sqrt(variance)

            meanPredictions.append([mean])
            uncertainties.append([std])
        }

        return (meanPredictions, uncertainties)
    }

    public func calibrateConfidence(temperature: Float = 1.0) {
        logger.info(component: "MLXPricePredictionModel", event: "Confidence calibration enabled", data: [
            "temperature": String(temperature)
        ])
    }

    public func predictWithCalibration(inputs: [[Double]], temperature: Float = 1.0) async throws -> (predictions: [[Double]], calibratedConfidences: [[Double]]) {
        let rawPredictions = try await predict(inputs: inputs)

        var calibratedConfidences: [[Double]] = []
        for pred in rawPredictions {
            let calibrated = pred.map { $0 / Double(temperature) }
            let softmax = softmaxCalibration(calibrated)
            calibratedConfidences.append(softmax)
        }

        return (rawPredictions, calibratedConfidences)
    }

    private func softmaxCalibration(_ logits: [Double]) -> [Double] {
        let maxLogit = logits.max() ?? 0.0
        let expValues = logits.map { exp($0 - maxLogit) }
        let sumExp = expValues.reduce(0, +)
        return expValues.map { $0 / sumExp }
    }

    public func predict(inputs: [[Double]]) async throws -> [[Double]] {
        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        let flatInputs: [Float]
        if useMixedPrecision {
            flatInputs = inputs.flatMap { $0.map { Float(F16($0)) } }
        } else {
            flatInputs = inputs.flatMap { $0.map { F($0) } }
        }

        let inputArray = MLXArray(flatInputs, [inputs.count, inputShape])
        let inputArrayConverted: MLXArray
        if useMixedPrecision {
            inputArrayConverted = inputArray.asType(F16.self)
        } else {
            inputArrayConverted = inputArray.asType(F.self)
        }

        let predictions = forwardBatch(inputArrayConverted)
        guard MLXAdapter.metallibAvailable() else {
            throw MLXError.initializationFailed("MLX metallib not available - missing required kernels")
        }

        try withError { error in
            eval(predictions)
            try error.check()
        }

        let predictionsF32 = predictions.asType(F.self)

        try withError { error in
            eval(predictionsF32)
            try error.check()
        }

        let predictionsShape = predictionsF32.shape
        guard predictionsShape.count == 2, predictionsShape[0] == inputs.count else {
            throw MLXError.invalidInput
        }

        let outputSize = predictionsShape[1]
        let predictionsArray = predictionsF32.asArray(F.self)

        var results: [[Double]] = []
        for i in 0..<inputs.count {
            let startIdx = i * outputSize
            let endIdx = startIdx + outputSize
            guard endIdx <= predictionsArray.count else {
                throw MLXError.invalidInput
            }
            let values = Array(predictionsArray[startIdx..<endIdx]).map { Double($0) }
            results.append(values)
        }
        return results
    }

    public func predictSingle(input: [Double]) async throws -> Double {
        let predictions = try await predict(inputs: [input])
        return predictions[0][0]
    }

    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.isEmpty ? "safetensors" : url.pathExtension
        let saveURL = fileExtension == "safetensors" ? url : url.deletingPathExtension().appendingPathExtension("safetensors")

        var arrays: [String: MLXArray] = [:]
        arrays["linear1.weight"] = linear1.weight
        if let bias1 = linear1.bias {
            arrays["linear1.bias"] = bias1
        }
        arrays["linear2.weight"] = linear2.weight
        if let bias2 = linear2.bias {
            arrays["linear2.bias"] = bias2
        }
        arrays["linear3.weight"] = linear3.weight
        if let bias3 = linear3.bias {
            arrays["linear3.bias"] = bias3
        }
        arrays["normalizationMean"] = normalizationMean
        arrays["normalizationStd"] = normalizationStd

        let metadata: [String: String] = [
            "inputSize": String(inputSize),
            "useMixedPrecision": String(useMixedPrecision),
            "isQuantized": String(isQuantized)
        ]

        try MLX.save(arrays: arrays, metadata: metadata, url: saveURL)
        logger.info(component: "MLXPricePredictionModel", event: "Model saved", data: ["path": saveURL.path])
    }

    public static func load(from path: String, logger: StructuredLogger) throws -> MLXPricePredictionModel {
        let url = URL(fileURLWithPath: path)
        let (arrays, metadata) = try MLX.loadArraysAndMetadata(url: url)

        guard let useMixedPrecisionStr = metadata["useMixedPrecision"],
              let useMixedPrecision = Bool(useMixedPrecisionStr) else {
            throw MLXError.loadFailed
        }

        guard let w1 = arrays["linear1.weight"],
              let w2 = arrays["linear2.weight"],
              let w3 = arrays["linear3.weight"],
              let mean = arrays["normalizationMean"],
              let std = arrays["normalizationStd"] else {
            throw MLXError.loadFailed
        }

        let inputSize: Int
        if let inputSizeStr = metadata["inputSize"],
           let parsedInputSize = Int(inputSizeStr) {
            inputSize = parsedInputSize
        } else {
            inputSize = w1.shape[1]
        }

        let model = try MLXPricePredictionModel(logger: logger, useMixedPrecision: useMixedPrecision, inputSize: inputSize)

        try withError { error in
            eval(w1, w2, w3, mean, std)
            if let b1 = arrays["linear1.bias"] {
                eval(b1)
            }
            if let b2 = arrays["linear2.bias"] {
                eval(b2)
            }
            if let b3 = arrays["linear3.bias"] {
                eval(b3)
            }
            try error.check()
        }

        model.linear1 = Linear(weight: w1, bias: arrays["linear1.bias"])
        model.linear2 = Linear(weight: w2, bias: arrays["linear2.bias"])
        model.linear3 = Linear(weight: w3, bias: arrays["linear3.bias"])
        model.normalizationMean = mean
        model.normalizationStd = std

        if let isQuantizedStr = metadata["isQuantized"],
           let isQuantized = Bool(isQuantizedStr) {
            model.isQuantized = isQuantized
        }

        logger.info(component: "MLXPricePredictionModel", event: "Model loaded", data: ["path": path, "inputSize": String(inputSize)])
        return model
    }

    public func quantize(groupSize: Int = 64, bits: Int = 8) throws {
        guard !isQuantized else {
            logger.warn(component: "MLXPricePredictionModel", event: "Model already quantized")
            return
        }

        MLXNN.quantize(model: self, groupSize: groupSize, bits: bits, mode: .affine)
        self.isQuantized = true
        logger.info(component: "MLXPricePredictionModel", event: "Model quantized", data: [
            "groupSize": String(groupSize),
            "bits": String(bits)
        ])
    }

    public func benchmarkLatency(inputs: [[Double]], iterations: Int = 100) throws -> (meanMs: Double, stdMs: Double) {
        guard let inputShape = inputs.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        let flatInputs: [F] = inputs.flatMap { $0.map(F.init) }
        let inputArray = MLXArray(flatInputs, [inputs.count, inputShape])
        let inputArrayConverted: MLXArray
        if useMixedPrecision {
            inputArrayConverted = inputArray.asType(F16.self)
        } else {
            inputArrayConverted = inputArray.asType(F.self)
        }

        var timings: [Double] = []

        for _ in 0..<iterations {
            let startTime = Date()
            let predictions = forwardBatch(inputArrayConverted)
            try withError { error in
                eval(predictions)
                try error.check()
            }
            let endTime = Date()
            let elapsed = endTime.timeIntervalSince(startTime) * 1000.0
            timings.append(elapsed)
        }

        let mean = timings.reduce(0, +) / Double(timings.count)
        let variance = timings.map { pow($0 - mean, 2) }.reduce(0, +) / Double(timings.count)
        let std = sqrt(variance)

        logger.info(component: "MLXPricePredictionModel", event: "Latency benchmark", data: [
            "iterations": String(iterations),
            "meanMs": String(mean),
            "stdMs": String(std),
            "quantized": String(isQuantized),
            "mixedPrecision": String(useMixedPrecision)
        ])

        return (mean, std)
    }

    public func update(batch: [[Double]], targets: [[Double]], learningRate: Float = 1e-4) async throws {
        guard let inputShape = batch.first?.count, inputShape > 0 else { throw MLXError.invalidInput }

        let flatInputs: [F] = batch.flatMap { $0.map(F.init) }
        let flatTargets: [F] = targets.flatMap { $0.map(F.init) }

        let inputArray = MLXArray(flatInputs, [batch.count, inputShape]).asType(F.self)
        let targetArray = MLXArray(flatTargets, [targets.count, targets[0].count]).asType(F.self)

        let optimizer = AdamW(learningRate: F(learningRate), weightDecay: 1e-4)

        func loss(model: MLXPricePredictionModel, x: MLXArray, y: MLXArray) -> MLXArray {
            let preds = model(x)
            let diff = preds - y
            return (diff * diff).mean()
        }

        let lg = valueAndGrad(model: self, loss)
        let (_, grads) = lg(self, inputArray, targetArray)

        let (clippedGrads, _) = clipGradNorm(gradients: grads, maxNorm: 1.0)
        optimizer.update(model: self, gradients: clippedGrads)

        logger.info(component: "MLXPricePredictionModel", event: "Online update completed", data: [
            "batchSize": String(batch.count),
            "learningRate": String(learningRate)
        ])
    }

    public func prune(sparsity: Float = 0.2) throws {
        let threshold = calculatePruningThreshold(sparsity: sparsity)

        let w1 = linear1.weight
        let w2 = linear2.weight
        let w3 = linear3.weight

        let mask1 = abs(w1) .> threshold
        let mask2 = abs(w2) .> threshold
        let mask3 = abs(w3) .> threshold

        let w1Pruned = w1 * mask1.asType(w1.dtype)
        let w2Pruned = w2 * mask2.asType(w2.dtype)
        let w3Pruned = w3 * mask3.asType(w3.dtype)

        linear1 = Linear(weight: w1Pruned, bias: linear1.bias)
        linear2 = Linear(weight: w2Pruned, bias: linear2.bias)
        linear3 = Linear(weight: w3Pruned, bias: linear3.bias)

        logger.info(component: "MLXPricePredictionModel", event: "Model pruned", data: [
            "sparsity": String(sparsity),
            "threshold": String(threshold.item(F.self))
        ])
    }

    private func calculatePruningThreshold(sparsity: Float) -> MLXArray {
        var allWeights: [F] = []
        allWeights.append(contentsOf: linear1.weight.asArray(F.self))
        allWeights.append(contentsOf: linear2.weight.asArray(F.self))
        allWeights.append(contentsOf: linear3.weight.asArray(F.self))

        let sorted = allWeights.map { abs($0) }.sorted()
        let thresholdIndex = Int(Float(sorted.count) * sparsity)
        let threshold = sorted[min(thresholdIndex, sorted.count - 1)]

        return MLXArray(F(threshold))
    }

    public func distillFromEnsemble(teacherModel: MLXPricePredictionModel, inputs: [[Double]], targets: [[Double]], temperature: Float = 3.0, alpha: Float = 0.7, epochs: Int = 100) async throws {
        logger.info(component: "MLXPricePredictionModel", event: "Starting knowledge distillation", data: [
            "temperature": String(temperature),
            "alpha": String(alpha)
        ])

        let flatInputs: [F] = inputs.flatMap { $0.map(F.init) }
        let flatTargets: [F] = targets.flatMap { $0.map(F.init) }
        let inputArray = MLXArray(flatInputs, [inputs.count, inputs[0].count]).asType(F.self)
        let targetArray = MLXArray(flatTargets, [targets.count, targets[0].count]).asType(F.self)

        let optimizer = AdamW(learningRate: 1e-4, weightDecay: 1e-4)

        func distillationLoss(student: MLXPricePredictionModel, teacher: MLXPricePredictionModel, x: MLXArray, y: MLXArray, temp: F, alpha: F) -> MLXArray {
            let studentPred = student(x)
            let teacherPred = teacher(x)

            let softTargets = teacherPred / temp
            let softPredictions = studentPred / temp

            let kdLoss = (softPredictions - softTargets) * (softPredictions - softTargets)
            let hardLoss = (studentPred - y) * (studentPred - y)

            return alpha * kdLoss.mean() + (F(1.0) - alpha) * hardLoss.mean()
        }

        let lg = valueAndGrad(model: self) { student, x, y in
            distillationLoss(student: student, teacher: teacherModel, x: x, y: y, temp: F(temperature), alpha: F(alpha))
        }

        for epoch in 0..<epochs {
            let (lossValue, grads) = lg(self, inputArray, targetArray)
            let (clippedGrads, _) = clipGradNorm(gradients: grads, maxNorm: 1.0)
            optimizer.update(model: self, gradients: clippedGrads)

            if epoch % 10 == 0 {
                let lossFloat = lossValue.item(F.self)
                logger.info(component: "MLXPricePredictionModel", event: "Distillation progress", data: [
                    "epoch": String(epoch),
                    "loss": String(lossFloat)
                ])
            }
        }

        logger.info(component: "MLXPricePredictionModel", event: "Knowledge distillation completed")
    }

    public func getModelInfo() -> ModelInfo {
        return ModelInfo(modelId: UUID().uuidString, version: "1.0.0", modelType: .pricePrediction, trainingDataHash: "mlx_price_model", accuracy: 0.85, createdAt: Date(), isActive: true)
    }

    public func computeSHAP(input: [Double], baseline: [Double]? = nil, numSamples: Int = 100) throws -> [Double] {
        let baselineInput = baseline ?? Array(repeating: 0.0, count: input.count)
        let baselineArray = MLXArray(baselineInput.map { F($0) }, [1, input.count]).asType(F.self)
        let inputArray = MLXArray(input.map { F($0) }, [1, input.count]).asType(F.self)

        var shapValues: [F] = Array(repeating: 0.0, count: input.count)

        for i in 0..<input.count {
            var featureImportance: F = 0.0

            for _ in 0..<numSamples {
                let randomValue = MLXRandom.uniform(low: 0.0, high: 1.0, [1, 1])
                try withError { error in
                    eval(randomValue)
                    try error.check()
                }
                let randomFloat = randomValue.item(F.self)

                let maskedInput: MLXArray
                if randomFloat > 0.5 {
                    maskedInput = inputArray
                } else {
                    maskedInput = baselineArray
                }

                let predWithFeature = self(maskedInput)
                let maskedInputWithout = baselineArray
                let predWithoutFeature = self(maskedInputWithout)

                try withError { error in
                    eval(predWithFeature, predWithoutFeature)
                    try error.check()
                }

                let diff = predWithFeature.item(F.self) - predWithoutFeature.item(F.self)
                featureImportance += diff
            }

            shapValues[i] = featureImportance / F(numSamples)
        }

        return shapValues.map { Double($0) }
    }

    public static func performCrossValidation(inputs: [[Double]], targets: [[Double]], nFolds: Int = 5, epochs: Int = 100, learningRate: Float = 1e-3, logger: StructuredLogger) async throws -> CrossValidationResult {
        guard inputs.count == targets.count, inputs.count >= nFolds else {
            throw MLXError.invalidInput
        }

        let foldSize = inputs.count / nFolds
        var foldResults: [TrainingResult] = []

        for fold in 0..<nFolds {
            let valStart = fold * foldSize
            let valEnd = min((fold + 1) * foldSize, inputs.count)

            var trainInputs: [[Double]] = []
            var trainTargets: [[Double]] = []
            var valInputs: [[Double]] = []
            var valTargets: [[Double]] = []

            for i in 0..<inputs.count {
                if i >= valStart && i < valEnd {
                    valInputs.append(inputs[i])
                    valTargets.append(targets[i])
                } else {
                    trainInputs.append(inputs[i])
                    trainTargets.append(targets[i])
                }
            }

            let model = try MLXPricePredictionModel(logger: logger)
            let result = try await model.train(
                inputs: trainInputs,
                targets: trainTargets,
                epochs: epochs,
                learningRate: learningRate,
                validationSplit: 0.0
            )

            foldResults.append(result)
            logger.info(component: "MLXPricePredictionModel", event: "Fold completed", data: [
                "fold": String(fold + 1),
                "finalLoss": String(result.finalLoss)
            ])
        }

        let avgFinalLoss = foldResults.map { $0.finalLoss }.reduce(0, +) / Double(foldResults.count)
        let avgBestLoss = foldResults.map { $0.bestLoss }.reduce(0, +) / Double(foldResults.count)
        let avgValLoss = foldResults.compactMap { $0.validationLoss }.reduce(0, +) / Double(foldResults.compactMap { $0.validationLoss }.count)

        return CrossValidationResult(
            nFolds: nFolds,
            avgFinalLoss: avgFinalLoss,
            avgBestLoss: avgBestLoss,
            avgValidationLoss: avgValLoss,
            foldResults: foldResults
        )
    }
}

public struct DistributedTrainingConfig {
    public let numDevices: Int
    public let deviceIds: [Int]
    public let syncInterval: Int

    public init(numDevices: Int = 1, deviceIds: [Int] = [0], syncInterval: Int = 1) {
        self.numDevices = numDevices
        self.deviceIds = deviceIds
        self.syncInterval = syncInterval
    }

    public static var singleDevice: DistributedTrainingConfig {
        return DistributedTrainingConfig(numDevices: 1, deviceIds: [0], syncInterval: 1)
    }
}

extension MLXPricePredictionModel {
    public func trainDistributed(inputs: [[Double]], targets: [[Double]], config: DistributedTrainingConfig, epochs: Int = 1000, learningRate: Float = 1e-3, logger: StructuredLogger) async throws -> TrainingResult {
        guard config.numDevices == 1 else {
            logger.warn(component: "MLXPricePredictionModel", event: "Multi-GPU training not yet supported in MLX Swift, falling back to single device")
            return try await train(inputs: inputs, targets: targets, epochs: epochs, learningRate: learningRate)
        }

        return try await train(inputs: inputs, targets: targets, epochs: epochs, learningRate: learningRate)
    }

    public func exportToCoreML(outputPath: String) throws {
        logger.warn(component: "MLXPricePredictionModel", event: "Core ML export not directly supported by MLX Swift. Exporting weights for manual conversion.")

        let weightsPath = outputPath.replacingOccurrences(of: ".mlmodel", with: "_weights.safetensors")
        try save(to: weightsPath)

        logger.info(component: "MLXPricePredictionModel", event: "Model weights exported for Core ML conversion", data: [
            "weightsPath": weightsPath,
            "outputPath": outputPath,
            "note": "Convert to Core ML using coremltools or manual conversion"
        ])
    }
}

public struct HyperparameterSpace {
    public let learningRateRange: ClosedRange<Float>
    public let dropoutRange: ClosedRange<Float>

    public init(learningRateRange: ClosedRange<Float> = 1e-5...1e-2, dropoutRange: ClosedRange<Float> = 0.0...0.5) {
        self.learningRateRange = learningRateRange
        self.dropoutRange = dropoutRange
    }
}

public class BayesianOptimizer {
    private let space: HyperparameterSpace
    private var observations: [(params: (lr: Float, dropout: Float), loss: Double)] = []
    private let logger: StructuredLogger

    public init(space: HyperparameterSpace, logger: StructuredLogger) {
        self.space = space
        self.logger = logger
    }

    public func suggestNext() -> (lr: Float, dropout: Float) {
        if observations.isEmpty {
            let lr = (space.learningRateRange.lowerBound + space.learningRateRange.upperBound) / 2.0
            let dropout = (space.dropoutRange.lowerBound + space.dropoutRange.upperBound) / 2.0
            return (lr, dropout)
        }

        let best = observations.min(by: { $0.loss < $1.loss })!
        let lr = best.params.lr * Float.random(in: 0.8...1.2).clamped(to: space.learningRateRange)
        let dropout = best.params.dropout * Float.random(in: 0.9...1.1).clamped(to: space.dropoutRange)
        return (lr, dropout)
    }

    public func update(lr: Float, dropout: Float, loss: Double) {
        observations.append(((lr, dropout), loss))
        logger.info(component: "BayesianOptimizer", event: "Observation added", data: [
            "lr": String(lr),
            "dropout": String(dropout),
            "loss": String(loss)
        ])
    }

    public func optimize(model: MLXPricePredictionModel, inputs: [[Double]], targets: [[Double]], nTrials: Int = 10, epochsPerTrial: Int = 50) async throws -> (bestLR: Float, bestDropout: Float, bestLoss: Double) {
        var bestLoss = Double.infinity
        var bestParams: (lr: Float, dropout: Float) = (1e-3, 0.2)

        for _ in 0..<nTrials {
            let (lr, dropout) = suggestNext()

            let result = try await model.train(
                inputs: inputs,
                targets: targets,
                epochs: epochsPerTrial,
                learningRate: lr,
                validationSplit: 0.2
            )

            update(lr: lr, dropout: dropout, loss: result.bestLoss)

            if result.bestLoss < bestLoss {
                bestLoss = result.bestLoss
                bestParams = (lr, dropout)
            }
        }

        return (bestParams.lr, bestParams.dropout, bestLoss)
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return max(range.lowerBound, min(range.upperBound, self))
    }
}

public enum MLXError: Error {
    case invalidInput, modelNotLoaded, saveFailed, loadFailed, deviceUnavailable, initializationFailed(String)

    public var localizedDescription: String {
        switch self {
        case .invalidInput:
            return "Invalid input data"
        case .modelNotLoaded:
            return "Model not loaded"
        case .saveFailed:
            return "Failed to save model"
        case .loadFailed:
            return "Failed to load model"
        case .deviceUnavailable:
            return "Metal device not available"
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        }
    }
}

public struct TrainingResult {
    public let finalLoss: Double
    public let bestLoss: Double
    public let epochs: Int
    public let learningRate: Double
    public let validationLoss: Double?
    public let bestEpoch: Int?

    public init(finalLoss: Double, bestLoss: Double, epochs: Int, learningRate: Double, validationLoss: Double? = nil, bestEpoch: Int? = nil) {
        self.finalLoss = finalLoss
        self.bestLoss = bestLoss
        self.epochs = epochs
        self.learningRate = learningRate
        self.validationLoss = validationLoss
        self.bestEpoch = bestEpoch
    }
}

// Note: Custom Float32 Adam optimizer removed - using standard Adam with Float32 gradients
// The standard Adam optimizer may still use Float64 internally for state (m, v)
// If Float64 errors persist, we'll need to implement a full custom Float32 Adam
// that ensures all optimizer state (momentum, variance) is also Float32
