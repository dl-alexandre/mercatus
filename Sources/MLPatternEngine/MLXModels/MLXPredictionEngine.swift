import Foundation
import Utils
import MLX
import MLXNN
import MLXOptimizers
import MLPatternEngine
import SmartVestorMLXAdapter

#if os(macOS)
import Metal
#endif

public class MLXPredictionEngine: PredictionEngineProtocol {
    private let logger: StructuredLogger
    private var priceModel: MLXPricePredictionModel?
    private var coinModels: [String: MLXPricePredictionModel] = [:]
    private var lstmModel: PortfolioLSTMForecaster?
    private var volatilityModel: MLXVolatilityPredictionModel?
    private var trendModel: MLXTrendClassificationModel?
    private var models: [ModelInfo.ModelType: ModelInfo] = [:]
    private var isInitialized = false
    private var useEnsemble: Bool = false
    private var ensembleMLPWeight: Double = 0.7
    private var ensembleLSTMWeight: Double = 0.3
    private var modelRegistry: ModelRegistry?

    public init(logger: StructuredLogger, modelRegistryPath: String? = nil) throws {
        self.logger = logger

        if let registryPath = modelRegistryPath {
            self.modelRegistry = ModelRegistry(registryPath: registryPath, logger: logger)
        } else {
            let defaultPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".mercatus/models")
            self.modelRegistry = ModelRegistry(registryPath: defaultPath, logger: logger)
        }

        #if os(macOS)
        let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"]
        let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"]

        if mlxDevice == "cpu" || disableMetal == "1" {
            let reason = mlxDevice == "cpu" ? "MLX_DEVICE=cpu set" : "MLX_DISABLE_METAL=1 set"
            logger.warn(component: "MLXPredictionEngine", event: "GPU disabled - \(reason)")
            throw MLXError.initializationFailed("GPU disabled: \(reason)")
        }

        if !MLXAdapter.shouldUseGPU() {
            let reason = ProcessInfo.processInfo.environment["SV_DISABLE_GPU"] == "1" ? "SV_DISABLE_GPU=1 set" :
                        "GPU not available or incompatible"
            logger.warn(component: "MLXPredictionEngine", event: "GPU disabled - \(reason)")
            throw MLXError.initializationFailed("GPU disabled: \(reason)")
        }

        guard MLXAdapter.metallibAvailable() else {
            logger.warn(component: "MLXPredictionEngine", event: "MLX metallib not available - GPU operations disabled. Build metallib with: ./scripts/build-mlx-metallib.sh")
            throw MLXError.initializationFailed("MLX metallib not available - missing required kernels (e.g., rbitsc). Build the correct metallib from MLX sources.")
        }

        // Configure MLX dtype FIRST, before any Linear layers are created
        MLXInitialization.configureMLX()

        do {
            try MLXAdapter.ensureInitialized()
            try MLXInitialization.ensureInitialized()
        } catch MLXAdapter.InitError.invalidMetallib {
            logger.warn(component: "MLXPredictionEngine", event: "Invalid MLX metallib or GPU initialization failed")
            throw MLXError.initializationFailed("Invalid MLX metallib or GPU backend fault. Use CPU mode.")
        } catch {
            logger.error(component: "MLXPredictionEngine", event: "MLX initialization failed", data: ["error": error.localizedDescription])
            throw MLXError.initializationFailed(error.localizedDescription)
        }
        #endif

        let priceModelInfo = ModelInfo(
            modelId: "mlx_price_prediction",
            version: "1.0.0",
            modelType: .pricePrediction,
            trainingDataHash: "mlx_price_model",
            accuracy: 0.85,
            createdAt: Date(),
            isActive: true
        )
        models[.pricePrediction] = priceModelInfo

        logger.info(component: "MLXPredictionEngine", event: "MLX prediction engine created (lazy initialization)")
    }

    private func ensureInitialized() throws {
        guard !isInitialized else { return }

        try MLXInitialization.ensureInitialized()

        let useMixedPrecision = ProcessInfo.processInfo.environment["MLX_USE_FLOAT16"] == "1"

        do {
            self.priceModel = try MLXPricePredictionModel(logger: logger, useMixedPrecision: useMixedPrecision)
            priceModel?.compile()

            let enableEnsemble = ProcessInfo.processInfo.environment["MLX_USE_ENSEMBLE"] == "1"
            let sequenceLength = Int(ProcessInfo.processInfo.environment["MLX_LSTM_SEQUENCE_LENGTH"] ?? "30") ?? 30
            if let mlpWeightStr = ProcessInfo.processInfo.environment["MLX_ENSEMBLE_MLP_WEIGHT"],
               let mlpWeight = Double(mlpWeightStr) {
                self.ensembleMLPWeight = mlpWeight
                self.ensembleLSTMWeight = 1.0 - mlpWeight
            }
            if enableEnsemble {
                self.lstmModel = PortfolioLSTMForecaster(sequenceLength: sequenceLength, nFeatures: 18, nOutputs: 1, logger: logger)
                self.useEnsemble = true
            }

            isInitialized = true
            logger.info(component: "MLXPredictionEngine", event: "MLX models initialized successfully", data: [
                "mixedPrecision": String(useMixedPrecision),
                "compiled": "true",
                "ensemble": String(useEnsemble)
            ])
        } catch {
            logger.error(component: "MLXPredictionEngine", event: "Failed to initialize MLX models", data: ["error": error.localizedDescription])
            throw MLXError.initializationFailed(error.localizedDescription)
        }
    }

    public func predictPrice(request: PredictionRequest) async throws -> PredictionResponse {
        guard models[.pricePrediction] != nil else {
            throw PredictionError.modelNotAvailable
        }

        try ensureInitialized()

        let symbol = request.symbol.replacingOccurrences(of: "-USD", with: "")

        if await checkForModelUpdate(symbol: symbol) {
            try await reloadModelForCoin(symbol: symbol)
        }

        let coinModel = try await getModelForCoin(symbol: symbol)

        guard let priceModel = coinModel else {
            throw PredictionError.modelNotAvailable
        }

        // Convert features to the format expected by MLX model
        let featureVector = convertFeaturesToVector(request.features)

        // Make prediction using MLX model with error handling
        // withError will catch MLX C++ errors and convert them to Swift errors
        let prediction: Double
        do {
            prediction = try await withError { error in
                let result = try await priceModel.predictSingle(input: featureVector)
                try error.check()
                return result
            }
        } catch let mlxError as MLX.MLXError {
            // Extract the actual error message from MLXError.caught(String)
            var errorMsg = mlxError.localizedDescription
            if case .caught(let message) = mlxError {
                errorMsg = message
            }
            logger.error(component: "MLXPredictionEngine", event: "MLX kernel error during prediction", data: [
                "error": errorMsg,
                "error_description": mlxError.localizedDescription,
                "symbol": request.symbol,
                "features_count": String(request.features.count)
            ])
            throw MLXError.initializationFailed("MLX kernel error: \(errorMsg)")
        } catch {
            logger.error(component: "MLXPredictionEngine", event: "Prediction failed", data: [
                "error": error.localizedDescription,
                "error_type": String(describing: type(of: error)),
                "symbol": request.symbol
            ])
            throw error
        }
        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: prediction,
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: models[.pricePrediction]!.version,
            timestamp: Date()
        )
    }

    public func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse {
        // For now, fall back to heuristic if MLX volatility model not available
        if let volatilityModel = volatilityModel {
            let featureVector = convertFeaturesToVector(request.features)
            let prediction = try await volatilityModel.predictSingle(input: featureVector)
            let confidence = calculateConfidence(features: request.features)
            let uncertainty = calculateUncertainty(features: request.features)

            return PredictionResponse(
                id: UUID().uuidString,
                prediction: prediction,
                confidence: confidence,
                uncertainty: uncertainty,
                modelVersion: models[.volatilityPrediction]?.version ?? "1.0.0",
                timestamp: Date()
            )
        } else {
            // Fallback to heuristic calculation
            return try await heuristicVolatilityPrediction(request: request)
        }
    }

    public func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse {
        // For now, fall back to heuristic if MLX trend model not available
        if let trendModel = trendModel {
            let featureVector = convertFeaturesToVector(request.features)
            let prediction = try await trendModel.predictSingle(input: featureVector)
            let confidence = calculateConfidence(features: request.features)
            let uncertainty = calculateUncertainty(features: request.features)

            return PredictionResponse(
                id: UUID().uuidString,
                prediction: prediction,
                confidence: confidence,
                uncertainty: uncertainty,
                modelVersion: models[.trendClassification]?.version ?? "1.0.0",
                timestamp: Date()
            )
        } else {
            // Fallback to heuristic calculation
            return try await heuristicTrendClassification(request: request)
        }
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        guard !requests.isEmpty else { return [] }

        try ensureInitialized()

        let priceRequests = requests.filter { $0.modelType == .pricePrediction }
        let volatilityRequests = requests.filter { $0.modelType == .volatilityPrediction }
        let trendRequests = requests.filter { $0.modelType == .trendClassification }

        var responses: [PredictionResponse] = []

        if !priceRequests.isEmpty {
            let priceResponses = try await batchPredictPrice(requests: priceRequests)
            responses.append(contentsOf: priceResponses)
        }

        for request in volatilityRequests {
            responses.append(try await predictVolatility(request: request))
        }

        for request in trendRequests {
            responses.append(try await classifyTrend(request: request))
        }

        return responses
    }

    private func batchPredictPrice(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        var responses: [PredictionResponse] = []

        for request in requests {
            let symbol = request.symbol.replacingOccurrences(of: "-USD", with: "")
            guard let coinModel = try await getModelForCoin(symbol: symbol) else {
                throw PredictionError.modelNotAvailable
            }

            let featureVector = convertFeaturesToVector(request.features)
            let prediction = try await coinModel.predictSingle(input: featureVector)

            let confidence = calculateConfidence(features: request.features)
            let uncertainty = calculateUncertainty(features: request.features)

            responses.append(PredictionResponse(
                id: UUID().uuidString,
                prediction: prediction,
                confidence: confidence,
                uncertainty: uncertainty,
                modelVersion: models[.pricePrediction]?.version ?? "1.0.0",
                timestamp: Date()
            ))
        }

        return responses
    }

    private func prepareSequenceData(requests: [PredictionRequest]) -> [[Float]] {
        return requests.map { request in
            let features = convertFeaturesToVector(request.features)
            return features.map { Float($0) }
        }
    }

    public func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return models[modelType]
    }

    public func trainPriceModel(trainingData: [[Double]], targets: [[Double]], epochs: Int = 1000, coinSymbol: String? = nil) async throws {
        try ensureInitialized()
        guard let priceModel = priceModel else {
            throw PredictionError.modelNotAvailable
        }

        let result = try await priceModel.train(inputs: trainingData, targets: targets, epochs: epochs, coinSymbol: coinSymbol)
        logger.info(component: "MLXPredictionEngine", event: "Trained price model", data: [
            "finalLoss": String(result.finalLoss),
            "epochs": String(result.epochs),
            "coinSymbol": coinSymbol ?? "none"
        ])

        if let symbol = coinSymbol {
            coinModels[symbol] = priceModel
            modelLoadTimes[symbol] = Date()
        }
    }

    public func loadModel(_ modelInfo: ModelInfo) {
        models[modelInfo.modelType] = modelInfo
        logger.info(component: "MLXPredictionEngine", event: "Loaded model", data: [
            "modelId": modelInfo.modelId,
            "modelType": modelInfo.modelType.rawValue
        ])
    }

    public func saveModelForCoin(symbol: String, model: MLXPricePredictionModel, trainingResult: TrainingResult) throws {
        let modelId = "\(symbol.lowercased())_price_prediction"
        let version = String(format: "%.0f", Date().timeIntervalSince1970)

        guard let registry = modelRegistry else {
            logger.warn(component: "MLXPredictionEngine", event: "Model registry not available, cannot save model")
            return
        }

        let metadata = ModelMetadata(
            architecture: "MLP",
            inputSize: 18,
            outputSize: 1,
            trainingEpochs: trainingResult.epochs,
            finalLoss: trainingResult.finalLoss,
            validationLoss: trainingResult.validationLoss,
            accuracy: trainingResult.validationLoss.map { 1.0 / (1.0 + $0) },
            hyperparameters: [
                "learningRate": String(trainingResult.learningRate)
            ]
        )

        _ = try registry.register(model: model, modelId: modelId, version: version, metadata: metadata)

        coinModels[symbol] = model

        logger.info(component: "MLXPredictionEngine", event: "Saved model for coin", data: [
            "symbol": symbol,
            "modelId": modelId,
            "version": version
        ])
    }

    public func reloadModelForCoin(symbol: String) async throws {
        coinModels.removeValue(forKey: symbol)
        modelLoadTimes.removeValue(forKey: symbol)

        if let registry = modelRegistry {
            let modelId = "\(symbol.lowercased())_price_prediction"
            if let loadedModel = try? registry.loadModel(modelId: modelId, version: nil, logger: logger) {
                coinModels[symbol] = loadedModel
                modelLoadTimes[symbol] = Date()
                logger.info(component: "MLXPredictionEngine", event: "Reloaded coin-specific model", data: ["symbol": symbol])
            }
        }
    }

    public func updateModelForCoin(symbol: String, batch: [[Double]], targets: [[Double]], learningRate: Float = 1e-4) async throws {
        guard let model = try await getModelForCoin(symbol: symbol) else {
            throw PredictionError.modelNotAvailable
        }

        try await model.update(batch: batch, targets: targets, learningRate: learningRate)

        coinModels[symbol] = model
        modelLoadTimes[symbol] = Date()

        if let registry = modelRegistry {
            let modelId = "\(symbol.lowercased())_price_prediction"
            let version = String(format: "%.0f", Date().timeIntervalSince1970)

            let metadata = ModelMetadata(
                architecture: "MLP",
                inputSize: 18,
                outputSize: 1,
                trainingEpochs: 1,
                finalLoss: 0.0,
                validationLoss: nil,
                accuracy: nil,
                hyperparameters: [
                    "learningRate": String(learningRate),
                    "updateType": "incremental"
                ]
            )

            _ = try? registry.register(model: model, modelId: modelId, version: version, metadata: metadata)
            logger.info(component: "MLXPredictionEngine", event: "Model updated incrementally", data: ["symbol": symbol])
        }
    }

    private func getModelForCoin(symbol: String, forceReload: Bool = false) async throws -> MLXPricePredictionModel? {
        if !forceReload, let cached = coinModels[symbol] {
            return cached
        }

        if let registry = modelRegistry {
            let modelId = "\(symbol.lowercased())_price_prediction"
            if let loadedModel = try? registry.loadModel(modelId: modelId, version: nil, logger: logger) {
                coinModels[symbol] = loadedModel
                modelLoadTimes[symbol] = Date()
                logger.info(component: "MLXPredictionEngine", event: "Loaded coin-specific model", data: ["symbol": symbol])
                return loadedModel
            }
        }

        if let fallback = priceModel {
            logger.debug(component: "MLXPredictionEngine", event: "Using fallback model for coin", data: ["symbol": symbol])
            return fallback
        }

        return nil
    }

    private var modelLoadTimes: [String: Date] = [:]

    private func checkForModelUpdate(symbol: String) async -> Bool {
        guard let registry = modelRegistry else { return false }

        let modelId = "\(symbol.lowercased())_price_prediction"
        guard let latestVersion = registry.getLatestVersion(modelId: modelId) else {
            return false
        }

        if let lastLoadTime = modelLoadTimes[symbol] {
            return latestVersion.createdAt > lastLoadTime
        }

        return coinModels[symbol] == nil
    }

    private func convertFeaturesToVector(_ features: [String: Double]) -> [Double] {
        let close = features["close"] ?? features["price"] ?? 0.0
        let closePrev = features["close_prev"] ?? close
        let ret = closePrev > 0 ? log(close / closePrev) : 0.0

        let ret1d = features["ret_1d"] ?? ret
        let ret5d = features["ret_5d"] ?? ret
        let ret20d = features["ret_20d"] ?? ret

        let vol = features["volume"] ?? 0.0
        let avgVol20d = features["avg_vol_20d"] ?? vol
        let volRatio = avgVol20d > 0 ? vol / avgVol20d : 1.0
        let volDelta = features["vol_delta"] ?? 0.0

        let roc14 = features["roc_14"] ?? 0.0
        let stochK = features["stoch_k"] ?? 50.0
        let stochD = features["stoch_d"] ?? 50.0

        let atr14 = features["atr_14"] ?? 0.0
        let atrRatio = close > 0 ? (features["atr_ratio"] ?? (atr14 / close)) : 0.0

        let bbWidth = features["bb_width"] ?? 0.0
        let cumDelta = features["cum_delta"] ?? 0.0
        let vwapDistance = features["vwap_distance"] ?? 0.0

        return [
            ret,
            ret1d,
            ret5d,
            ret20d,
            volRatio,
            volDelta,
            roc14,
            stochK,
            stochD,
            atrRatio,
            bbWidth,
            cumDelta,
            vwapDistance,
            features["rsi"] ?? 50.0,
            features["macd"] ?? 0.0,
            features["macd_signal"] ?? 0.0,
            features["volatility"] ?? 0.0,
            close
        ]
    }

    public func computeNormalizationStats(trainingData: [[Double]]) throws {
        guard !trainingData.isEmpty, let featureCount = trainingData.first?.count, featureCount == 18 else {
            throw MLXError.invalidInput
        }

        try ensureInitialized()
        guard let priceModel = priceModel else {
            throw PredictionError.modelNotAvailable
        }

        var means = Array(repeating: 0.0, count: featureCount)
        var variances = Array(repeating: 0.0, count: featureCount)

        for sample in trainingData {
            for (idx, value) in sample.enumerated() {
                means[idx] += value
            }
        }

        for idx in 0..<featureCount {
            means[idx] /= Double(trainingData.count)
        }

        for sample in trainingData {
            for (idx, value) in sample.enumerated() {
                let diff = value - means[idx]
                variances[idx] += diff * diff
            }
        }

        for idx in 0..<featureCount {
            variances[idx] /= Double(trainingData.count)
        }

        let stds = variances.map { sqrt($0) }

        try priceModel.updateNormalization(mean: means, std: stds)

        logger.info(component: "MLXPredictionEngine", event: "Normalization statistics computed from training data", data: [
            "samples": String(trainingData.count),
            "features": String(featureCount)
        ])
    }

    private func calculateConfidence(features: [String: Double]) -> Double {
        let requiredFeatures = ["price", "volatility", "rsi", "macd"]
        let availableFeatures = requiredFeatures.filter { features[$0] != nil }.count
        let featureCompleteness = Double(availableFeatures) / Double(requiredFeatures.count)

        let volatility = features["volatility"] ?? 0.0
        let volatilityPenalty = min(1.0, volatility * 2.0)

        return featureCompleteness * (1.0 - volatilityPenalty * 0.3)
    }

    private func calculateUncertainty(features: [String: Double]) -> Double {
        let volatility = features["volatility"] ?? 0.0
        let priceChange = abs(features["price_change"] ?? 0.0)
        let volumeChange = abs(features["volume_change"] ?? 0.0)

        let baseUncertainty = volatility * 0.5
        let changeUncertainty = (priceChange + volumeChange) * 0.3

        return min(1.0, baseUncertainty + changeUncertainty)
    }

    private func heuristicVolatilityPrediction(request: PredictionRequest) async throws -> PredictionResponse {
        let currentVolatility = request.features["volatility"] ?? 0.0
        let priceChange = request.features["price_change"] ?? 0.0
        let volumeChange = request.features["volume_change"] ?? 0.0

        let timeMultiplier = request.timeHorizon / 3600.0

        let priceVolatilityComponent = abs(priceChange) * timeMultiplier
        let volumeVolatilityComponent = abs(volumeChange) * timeMultiplier * 0.5

        let prediction = currentVolatility * (1.0 + priceVolatilityComponent + volumeVolatilityComponent)

        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: max(0.0, prediction),
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: "heuristic_fallback",
            timestamp: Date()
        )
    }

    private func heuristicTrendClassification(request: PredictionRequest) async throws -> PredictionResponse {
        let trendStrength = request.features["trend_strength"] ?? 0.0
        let rsi = request.features["rsi"] ?? 50.0
        let macd = request.features["macd"] ?? 0.0
        let macdSignal = request.features["macd_signal"] ?? 0.0

        let trendScore = trendStrength * 0.4
        let rsiScore = (rsi - 50.0) / 50.0 * 0.3
        let macdScore = (macd - macdSignal) * 0.3

        let classification = trendScore + rsiScore + macdScore

        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: max(-1.0, min(1.0, classification)),
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: "heuristic_fallback",
            timestamp: Date()
        )
    }
}

// Placeholder classes for future MLX volatility and trend models
public class MLXVolatilityPredictionModel {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictSingle(input: [Double]) async throws -> Double {
        // Placeholder - return simple heuristic for now
        logger.warn(component: "MLXVolatilityPredictionModel", event: "MLX volatility model not implemented, using heuristic")
        return input.first ?? 0.0 * 0.1 // Simple placeholder
    }
}

public class MLXTrendClassificationModel {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictSingle(input: [Double]) async throws -> Double {
        // Placeholder - return simple heuristic for now
        logger.warn(component: "MLXTrendClassificationModel", event: "MLX trend model not implemented, using heuristic")
        return 0.0 // Neutral trend placeholder
    }
}
