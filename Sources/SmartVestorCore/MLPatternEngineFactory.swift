import Foundation
import MLPatternEngine
import Utils
import Core

#if canImport(MLPatternEngineMLX) && !NO_MLX
import MLPatternEngineMLX
#endif

public class MLPatternEngineFactory {
    private let logger: StructuredLogger
    private let useMLXModels: Bool

    public init(logger: StructuredLogger, useMLXModels: Bool = false) {
        self.logger = logger
        self.useMLXModels = useMLXModels
    }

    public func createMLPatternEngine() async throws -> MLPatternEngine {
        logger.info(component: "MLPatternEngineFactory", event: "Creating MLPatternEngine instance")

        let database = try SQLiteTimeSeriesDatabase(logger: logger)
        let timeSeriesStore = TimeSeriesStore(database: database, logger: logger)
        let qualityValidator = DataQualityValidator(logger: logger)

        let dataIngestionService = DataIngestionService(
            exchangeConnectors: [:],
            qualityValidator: qualityValidator,
            timeSeriesStore: timeSeriesStore,
            logger: logger
        )

        let technicalIndicators = TechnicalIndicators()
        let featureExtractor = FeatureExtractor(
            technicalIndicators: technicalIndicators,
            logger: logger
        )

        let patternStorageService = PatternStorageService(
            database: database,
            logger: logger
        )
        let patternRecognizer = PatternRecognizer(
            logger: logger,
            patternStorage: patternStorageService
        )

        let predictionEngine: PredictionEngineProtocol
        let volatilityPredictor: VolatilityPredictionProtocol
        let trendClassifier: TrendClassificationProtocol
        let predictionValidator = PredictionValidator(logger: logger)
        let modelManager = ModelManager(logger: logger)
        let cacheManager = MockCacheManager(logger: logger)
        let circuitBreaker = MockCircuitBreaker()

        if useMLXModels {
            logger.info(component: "MLPatternEngineFactory", event: "Using MLX-based models")
            #if canImport(MLPatternEngineMLX) && !NO_MLX
            predictionEngine = try MLXPredictionEngine(logger: logger)
            volatilityPredictor = GARCHVolatilityPredictor(logger: logger)
            trendClassifier = TrendClassifier(
                logger: logger,
                technicalIndicators: technicalIndicators
            )
            logger.info(component: "MLPatternEngineFactory", event: "MLX prediction engine created (will initialize on first use)")
            #else
            throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLX not available but MLX models requested"])
            #endif
        } else {
            throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Traditional models disabled - MLX only"])
        }

        let bootstrapTrainer = BootstrapTrainer(
            logger: logger,
            featureExtractor: featureExtractor,
            predictionValidator: predictionValidator,
            modelManager: modelManager
        )

        let inferenceService = InferenceService(
            predictionEngine: predictionEngine,
            cacheManager: cacheManager,
            circuitBreaker: circuitBreaker,
            logger: logger
        )

        let modelPrice = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .pricePrediction)
        let modelVolatility = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .volatilityPrediction)
        let modelTrend = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .trendClassification)

        if useMLXModels {
            #if canImport(MLPatternEngineMLX) && !NO_MLX
            if let mlxEngine = predictionEngine as? MLXPredictionEngine {
                mlxEngine.loadModel(modelPrice)
                mlxEngine.loadModel(modelVolatility)
                mlxEngine.loadModel(modelTrend)
            } else if let concreteEngine = predictionEngine as? PredictionEngine {
                concreteEngine.loadModel(modelPrice)
                concreteEngine.loadModel(modelVolatility)
                concreteEngine.loadModel(modelTrend)
            }
            #else
            if let concreteEngine = predictionEngine as? PredictionEngine {
                concreteEngine.loadModel(modelPrice)
                concreteEngine.loadModel(modelVolatility)
                concreteEngine.loadModel(modelTrend)
            }
            #endif
        } else {
            if let concreteEngine = predictionEngine as? PredictionEngine {
                concreteEngine.loadModel(modelPrice)
                concreteEngine.loadModel(modelVolatility)
                concreteEngine.loadModel(modelTrend)
            }
        }

        // Fetch and seed historical data from market data providers
        try await seedHistoricalDataFromProviders(into: database)

        // Train MLX models if using MLX
        if useMLXModels {
            #if canImport(MLPatternEngineMLX) && !NO_MLX
            if let mlxEngine = predictionEngine as? MLXPredictionEngine {
                do {
                    try await trainMLXModels(engine: mlxEngine, database: database)
                } catch {
                    logger.warn(component: "MLPatternEngineFactory", event: "MLX model training failed", data: ["error": error.localizedDescription])
                }
            }
            #endif
        }

        let mlEngine = MLPatternEngine(
            dataIngestionService: dataIngestionService,
            featureExtractor: featureExtractor,
            patternRecognizer: patternRecognizer,
            predictionEngine: predictionEngine,
            volatilityPredictor: volatilityPredictor,
            trendClassifier: trendClassifier,
            predictionValidator: predictionValidator,
            bootstrapTrainer: bootstrapTrainer,
            modelManager: modelManager,
            inferenceService: inferenceService,
            logger: logger
        )

        logger.info(component: "MLPatternEngineFactory", event: "MLPatternEngine created successfully")
        return mlEngine
    }

    public func createMLXTrainingPipeline() throws {
        logger.warn(component: "MLPatternEngineFactory", event: "MLX training pipeline not yet implemented")
        throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLX integration not yet implemented"])
    }

    private func seedHistoricalDataFromProviders(into database: DatabaseProtocol) async throws {
        let dynamic: [String]
        do {
            dynamic = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger)
        } catch {
            logger.warn(component: "MLPatternEngineFactory", event: "robinhood_api_failed", data: [
                "error": error.localizedDescription,
                "message": "Falling back to static list"
            ])
            dynamic = []
        }
        let symbols = dynamic.isEmpty ? [
            "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
            "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
            "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
            "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
            "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
            "VIRTUAL", "ZORA"
        ] : dynamic
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -180, to: endDate) else {
        logger.error(component: "MLPatternEngineFactory", event: "Failed to calculate start date")
        return
        }

        var symbolsNeedingData: [String] = []

        for symbol in symbols {
        let count = try await checkDataExists(database: database, symbol: symbol, from: startDate, to: endDate)
        if count < 50 {
            symbolsNeedingData.append(symbol)
        }
        }

        guard !symbolsNeedingData.isEmpty else {
            logger.info(component: "MLPatternEngineFactory", event: "All symbols have cached data, skipping fetch")
            return
        }

        logger.info(component: "MLPatternEngineFactory", event: "Fetching historical data for missing symbols", data: [
            "symbols": String(symbolsNeedingData.count)
        ])

        let marketDataProvider = MultiProviderMarketDataProvider()

        for symbol in symbolsNeedingData {
            do {
                let data = try await marketDataProvider.getHistoricalData(
                    startDate: startDate,
                    endDate: endDate,
                    symbols: [symbol]
                )

                if let historicalData = data[symbol], !historicalData.isEmpty {
                    try await insertDataDirectly(into: database, points: historicalData, symbol: symbol)

                    logger.info(component: "MLPatternEngineFactory", event: "Inserted data for symbol", data: [
                        "symbol": symbol,
                        "points": String(historicalData.count)
                    ])
                }
            } catch {
                logger.warn(component: "MLPatternEngineFactory", event: "Failed to fetch data", data: [
                    "symbol": symbol,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func checkTotalDataExists(database: DatabaseProtocol) async throws -> Int {
        let sql = """
        SELECT COUNT(*) as count
        FROM market_data;
        """

        let rows = try await database.executeQuery(sql, parameters: [])

        if let firstRow = rows.first,
           let countValue = firstRow["count"] {
            if let count = countValue as? Int {
                return count
            } else if let count = countValue as? Int32 {
                return Int(count)
            } else if let count = countValue as? Double {
                return Int(count)
            }
        }
        return 0
    }

    private func checkDataExists(database: DatabaseProtocol, symbol: String, from: Date, to: Date) async throws -> Int {
        let sql = """
        SELECT COUNT(*) as count
        FROM market_data
        WHERE symbol = ? AND timestamp BETWEEN ? AND ?;
        """

        let rows = try await database.executeQuery(sql, parameters: [
            "\(symbol)-USD",
            from.timeIntervalSince1970,
            to.timeIntervalSince1970
        ])

        if let firstRow = rows.first,
           let countValue = firstRow["count"] {
            if let count = countValue as? Int {
                return count
            } else if let count = countValue as? Int32 {
                return Int(count)
            } else if let count = countValue as? Double {
                return Int(count)
            }
        }
        return 0
    }

    private func insertDataDirectly(into database: DatabaseProtocol, points: [SmartVestor.MarketDataPoint], symbol: String) async throws {
        let validPoints = points
        guard !validPoints.isEmpty else {
            logger.warn(component: "MLPatternEngineFactory", event: "No data points to insert", data: ["symbol": symbol])
            return
        }

        // Insert data using raw SQL
        let batchSize = 100
        let batches = validPoints.chunked(into: batchSize)

        for batch in batches {
            for point in batch {
                let sql = """
                INSERT OR REPLACE INTO market_data(symbol, exchange, timestamp, open, high, low, close, volume)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?);
                """

                let parameters: [any Sendable] = [
                    "\(symbol)-USD",
                    "provider",
                    point.timestamp.timeIntervalSince1970,
                    point.open,
                    point.high,
                    point.low,
                    point.close,
                    point.volume
                ]

                _ = try await database.executeUpdate(sql, parameters: parameters)
            }

            // Force checkpoint after each batch to ensure data is immediately readable
            let checkpointSQL = "PRAGMA wal_checkpoint(FULL);"
            _ = try? await database.executeUpdate(checkpointSQL, parameters: [])
        }
    }

    #if canImport(MLPatternEngineMLX) && !NO_MLX
    private let cacheManager = OptimizedCacheManager(logger: StructuredLogger())
    private var prefetchQueue: [String] = []

    // Helper function to extract properties and call the MLPatternEngine adapter
    // database.getMarketData returns MLPatternEngine.MarketDataPoint at runtime
    // FeatureExtractor.extractFeatures expects MLPatternEngine.MarketDataPoint
    // We extract properties and recreate instances using the protocol's type signature
    private func callExtractFeaturesAdapter(
        extractor: FeatureExtractorProtocol,
        currentPoint: Any,
        historicalPoints: [Any]
    ) async throws -> FeatureSet {
        func extractProperties(_ point: Any) -> (timestamp: Date, symbol: String, open: Double, high: Double, low: Double, close: Double, volume: Double, exchange: String) {
            let mirror = Mirror(reflecting: point)
            var timestamp: Date?
            var symbol: String?
            var open: Double?
            var high: Double?
            var low: Double?
            var close: Double?
            var volume: Double?
            var exchange: String?

            for child in mirror.children {
                if let label = child.label {
                    switch label {
                    case "timestamp": timestamp = child.value as? Date
                    case "symbol": symbol = child.value as? String
                    case "open": open = child.value as? Double
                    case "high": high = child.value as? Double
                    case "low": low = child.value as? Double
                    case "close": close = child.value as? Double
                    case "volume": volume = child.value as? Double
                    case "exchange": exchange = child.value as? String
                    default: break
                    }
                }
            }

            return (
                timestamp: timestamp ?? Date(),
                symbol: symbol ?? "",
                open: open ?? 0.0,
                high: high ?? 0.0,
                low: low ?? 0.0,
                close: close ?? 0.0,
                volume: volume ?? 0.0,
                exchange: exchange ?? ""
            )
        }

        let currentProps = extractProperties(currentPoint)
        let historicalProps = historicalPoints.map { extractProperties($0) }

        // Use adapter function from MLPatternEngine module
        // That module's MarketDataPoint resolves to MLPatternEngine.MarketDataPoint
        // The adapter creates proper instances and calls extractFeatures
        // Call the global function directly (imported from MLPatternEngine module)
        return try await extractFeaturesAdapter(
            extractor: extractor,
            currentProps: currentProps,
            historicalProps: historicalProps
        )
    }

    // Helper function to get MarketDataPoint array with correct type
    // database.getMarketData returns MLPatternEngine.MarketDataPoint (from DatabaseProtocol)
    // We need to ensure the type is correctly inferred
    private func getCachedOrFetchData(symbol: String, database: DatabaseProtocol, days: Int) async throws -> [Any] {
        let cacheKey = "\(symbol)-\(days)"

        // TEMPORARILY DISABLED: Swift 6 strict concurrency issues with [Any] Sendable
        // let cachedRaw: Any? = await cacheManager.get(cacheKey) as Any?
        // let cached = cachedRaw as? [Any]
        // if let cached = cached {
        //     logger.debug(component: "MLPatternEngineFactory", event: "Using cached training data", data: ["symbol": symbol, "samples": String(cached.count)])
        //     return cached
        // }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate start date"])
        }

        let dbDataRaw = try await database.getMarketData(symbol: symbol, from: startDate, to: endDate)
        let dataArray: [Any] = Array(dbDataRaw.map { $0 as Any })
        // TEMPORARILY DISABLED: Swift 6 concurrency issues
        // await cacheManager.set(cacheKey, value: dataArray, compress: true)
        return dataArray
    }

    private func prewarmCache(database: DatabaseProtocol) async {
        let topCoins = ["BTC", "ETH", "SOL", "ADA", "DOGE"]
        let days = [30, 90, 180]

        var keysToLoad: [String] = []
        for coin in topCoins {
            for day in days {
                keysToLoad.append("\(coin)-USD-\(day)")
            }
        }

        let db = database
        // TEMPORARILY DISABLED: Swift 6 concurrency issues
        // await cacheManager.prewarm(keys: keysToLoad) { @Sendable key in
        //     let parts = key.split(separator: "-")
        //     guard parts.count >= 2 else { return nil }
        //     let symbol = "\(parts[0])-USD"
        //     let days = Int(parts.last ?? "180") ?? 180
        //
        //     let endDate = Date()
        //     guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
        //         return nil
        //     }
        //
        //     let data = try? await db.getMarketData(symbol: symbol, from: startDate, to: endDate)
        //     return data?.map { $0 as Any }
        // }

        logger.info(component: "MLPatternEngineFactory", event: "Cache pre-warmed", data: ["keys": String(keysToLoad.count)])
    }

    private func prefetchNextCoin(symbols: [String], currentIndex: Int, database: DatabaseProtocol, days: Int) {
        guard currentIndex + 1 < symbols.count else { return }
        let nextSymbol = symbols[currentIndex + 1]
        let cacheMgr = cacheManager
        Task {
            let cacheKey = "\(nextSymbol)-\(days)"
            if await cacheMgr.get(cacheKey) == nil {
                let endDate = Date()
                if let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) {
                    let dbDataRaw = try? await database.getMarketData(symbol: nextSymbol, from: startDate, to: endDate)
                    if let dataArray = dbDataRaw?.map({ $0 as Any }) {
                        await cacheMgr.set(cacheKey, value: dataArray, compress: true)
                    }
                }
            }
        }
    }

    private func augmentWithNoise(inputs: [[Double]], targets: [[Double]], sigma: Double = 0.001, multiplier: Int = 5) -> ([[Double]], [[Double]]) {
        var augmentedInputs: [[Double]] = inputs
        var augmentedTargets: [[Double]] = targets

        for _ in 0..<multiplier {
            for (idx, input) in inputs.enumerated() {
                let noisyInput = input.map { $0 + Double.random(in: -sigma...sigma) }
                augmentedInputs.append(noisyInput)
                augmentedTargets.append(targets[idx])
            }
        }

        return (augmentedInputs, augmentedTargets)
    }

    private func randomCropAndScale(data: [Any], minWindow: Int = 40, maxWindow: Int = 60) -> [Any]? {
        guard data.count >= maxWindow, minWindow <= maxWindow, minWindow > 0 else { return nil }
        let effectiveMaxWindow = min(maxWindow, data.count)
        guard effectiveMaxWindow >= minWindow else { return nil }
        let windowSize = Int.random(in: minWindow...effectiveMaxWindow)
        guard windowSize > 0, windowSize <= data.count else { return nil }
        let maxStartIdx = data.count - windowSize
        guard maxStartIdx >= 0 else { return nil }
        let startIdx: Int
        if maxStartIdx == 0 {
            startIdx = 0
        } else {
            startIdx = Int.random(in: 0...maxStartIdx)
        }
        guard startIdx >= 0, startIdx + windowSize <= data.count else { return nil }
        let cropped = Array(data[startIdx..<(startIdx + windowSize)])

        let scaleFactor = Double.random(in: 0.95...1.05)
        // Create new instances with scaled values
        // Use Mirror to extract properties since type resolution is ambiguous
        let result = cropped.compactMap { point -> Any? in
            let mirror = Mirror(reflecting: point)
            var timestamp: Date?
            var symbol: String?
            var open: Double?
            var high: Double?
            var low: Double?
            var close: Double?
            var volume: Double?
            var exchange: String?

            for child in mirror.children {
                if let label = child.label {
                    switch label {
                    case "timestamp": timestamp = child.value as? Date
                    case "symbol": symbol = child.value as? String
                    case "open": open = child.value as? Double
                    case "high": high = child.value as? Double
                    case "low": low = child.value as? Double
                    case "close": close = child.value as? Double
                    case "volume": volume = child.value as? Double
                    case "exchange": exchange = child.value as? String
                    default: break
                    }
                }
            }

            guard let ts = timestamp, let sym = symbol, let o = open, let h = high, let l = low, let c = close, let v = volume, let e = exchange else {
                return nil
            }

            let mlPoint = createMarketDataPoint(
                timestamp: ts,
                symbol: sym,
                open: o * scaleFactor,
                high: h * scaleFactor,
                low: l * scaleFactor,
                close: c * scaleFactor,
                volume: v,
                exchange: e
            )
            return mlPoint
        }
        return result.isEmpty ? nil : result
    }

    private func extractTrainingSamples(from historicalData: [Any], featureExtractor: FeatureExtractor, windowSize: Int, enableAugmentation: Bool = false) async -> ([[Double]], [[Double]]) {
        var trainingInputs: [[Double]] = []
        var trainingTargets: [[Double]] = []

        guard historicalData.count > windowSize else {
            return (trainingInputs, trainingTargets)
        }

        func extractTimestamp(_ point: Any) -> Date {
            let mirror = Mirror(reflecting: point)
            for child in mirror.children {
                if child.label == "timestamp", let ts = child.value as? Date {
                    return ts
                }
            }
            return Date()
        }

        func extractClose(_ point: Any) -> Double {
            let mirror = Mirror(reflecting: point)
            for child in mirror.children {
                if child.label == "close", let close = child.value as? Double {
                    return close
                }
            }
            return 0.0
        }

        let sortedData = historicalData.sorted { extractTimestamp($0) < extractTimestamp($1) }

        guard sortedData.count > windowSize else {
            return (trainingInputs, trainingTargets)
        }

        var dataToProcess = [sortedData]
        if enableAugmentation {
            for _ in 0..<3 {
                if let augmented = randomCropAndScale(data: sortedData) {
                    dataToProcess.append(augmented)
                }
            }
        }

        for data in dataToProcess {
            guard data.count > windowSize else { continue }
            for i in windowSize..<data.count {
                let currentData = data[i]
                let historicalWindow = Array(data[i-windowSize..<i])
                do {
                    let featureSet = try await callExtractFeaturesAdapter(
                        extractor: featureExtractor,
                        currentPoint: currentData,
                        historicalPoints: historicalWindow
                    )
                    let featureVector = convertFeaturesToTrainingVector(featureSet.features)
                    let targetPrice = extractClose(currentData)
                    trainingInputs.append(featureVector)
                    trainingTargets.append([targetPrice])
                } catch {
                    logger.debug(component: "MLPatternEngineFactory", event: "Feature extraction failed for window", data: ["index": String(i), "error": error.localizedDescription])
                }
            }
        }

        return (trainingInputs, trainingTargets)
    }

    private func trainMLXModels(engine: MLXPredictionEngine, database: DatabaseProtocol) async throws {
        logger.info(component: "MLPatternEngineFactory", event: "Training MLX models with enhanced data pipeline")

        await prewarmCache(database: database)
        await cacheManager.clearExpired()

        let topCoins = ["BTC", "ETH", "SOL", "ADA", "DOGE", "LINK", "UNI", "AVAX", "DOT", "MATIC", "LTC", "BCH", "XRP", "ETC", "AAVE", "COMP", "CRV", "MKR", "SNX", "USDC"]

        let featureExtractor = FeatureExtractor(technicalIndicators: TechnicalIndicators(), logger: logger)
        let windowSize = 50

        var allTrainingInputs: [[Double]] = []
        var allTrainingTargets: [[Double]] = []

        logger.info(component: "MLPatternEngineFactory", event: "Multi-coin pretraining", data: ["coins": String(topCoins.count), "days": "180"])

        if let sqliteDB = database as? SQLiteTimeSeriesDatabase {
            let symbols = topCoins.map { "\($0)-USD" }
            let endDate = Date()
            guard let startDate = Calendar.current.date(byAdding: .day, value: -180, to: endDate) else {
                throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate start date"])
            }

            let batchData = try await sqliteDB.getMarketDataBatch(symbols: symbols, from: startDate, to: endDate)

            for (idx, coinSymbol) in topCoins.enumerated() {
                let symbol = "\(coinSymbol)-USD"
                if let historicalData = batchData[symbol] {
                    let dataArray: [Any] = Array(historicalData.map { $0 as Any })
                    let count = dataArray.count
                    let cacheKey = "\(symbol)-180"
                    // await cacheManager.set(cacheKey, value: dataArray, compress: true)

                    guard count > windowSize else {
                        logger.debug(component: "MLPatternEngineFactory", event: "Skipping coin - insufficient data", data: ["symbol": coinSymbol, "count": String(count)])
                        continue
                    }

                    let (inputs, targets) = await extractTrainingSamples(
                        from: dataArray,
                        featureExtractor: featureExtractor,
                        windowSize: windowSize,
                        enableAugmentation: coinSymbol == "BTC"
                    )

                    allTrainingInputs.append(contentsOf: inputs)
                    allTrainingTargets.append(contentsOf: targets)

                    logger.debug(component: "MLPatternEngineFactory", event: "Processed coin", data: ["symbol": coinSymbol, "samples": String(inputs.count), "progress": "\(idx + 1)/\(topCoins.count)"])
                }
            }
        } else {
            for (idx, coinSymbol) in topCoins.enumerated() {
                let symbol = "\(coinSymbol)-USD"
                prefetchNextCoin(symbols: topCoins, currentIndex: idx, database: database, days: 180)

                do {
                    let historicalData = try await getCachedOrFetchData(symbol: symbol, database: database, days: 180)

                    guard historicalData.count > windowSize else {
                        logger.debug(component: "MLPatternEngineFactory", event: "Skipping coin - insufficient data", data: ["symbol": coinSymbol, "count": String(historicalData.count)])
                        continue
                    }

                    let (inputs, targets) = await extractTrainingSamples(
                        from: historicalData,
                        featureExtractor: featureExtractor,
                        windowSize: windowSize,
                        enableAugmentation: coinSymbol == "BTC"
                    )

                    if coinSymbol == "BTC" {
                        allTrainingInputs.append(contentsOf: inputs)
                        allTrainingTargets.append(contentsOf: targets)
                        logger.info(component: "MLPatternEngineFactory", event: "BTC samples extracted", data: ["samples": String(inputs.count)])
                    } else {
                        allTrainingInputs.append(contentsOf: inputs)
                        allTrainingTargets.append(contentsOf: targets)
                    }

                    logger.debug(component: "MLPatternEngineFactory", event: "Processed coin", data: ["symbol": coinSymbol, "samples": String(inputs.count), "progress": "\(idx + 1)/\(topCoins.count)"])
                } catch {
                    logger.warn(component: "MLPatternEngineFactory", event: "Failed to process coin", data: ["symbol": coinSymbol, "error": error.localizedDescription])
                }
            }
        }

        guard !allTrainingInputs.isEmpty else {
            logger.warn(component: "MLPatternEngineFactory", event: "No training samples extracted")
            return
        }

        logger.info(component: "MLPatternEngineFactory", event: "Total samples before augmentation", data: ["samples": String(allTrainingInputs.count)])

        let (augmentedInputs, augmentedTargets) = augmentWithNoise(inputs: allTrainingInputs, targets: allTrainingTargets, sigma: 0.001, multiplier: 5)

        logger.info(component: "MLPatternEngineFactory", event: "Total samples after augmentation", data: ["samples": String(augmentedInputs.count)])

        let maxSamples = 10000
        let trainingBatch = Array(augmentedInputs.prefix(maxSamples))
        let targetBatch = Array(augmentedTargets.prefix(maxSamples))

        logger.info(component: "MLPatternEngineFactory", event: "Training BTC model with multi-coin data", data: ["samples": String(trainingBatch.count)])

        try await engine.trainPriceModel(trainingData: trainingBatch, targets: targetBatch, epochs: 50, coinSymbol: "BTC")

        logger.info(component: "MLPatternEngineFactory", event: "BTC model training completed", data: ["samples": String(trainingBatch.count)])

        logger.info(component: "MLPatternEngineFactory", event: "Transfer learning: fine-tuning BTC model for USDC")

        let usdcData = try await getCachedOrFetchData(symbol: "USDC-USD", database: database, days: 180)
        if usdcData.count > windowSize {
            let (usdcInputs, usdcTargets) = await extractTrainingSamples(
                from: usdcData,
                featureExtractor: featureExtractor,
                windowSize: windowSize,
                enableAugmentation: false
            )

            if !usdcInputs.isEmpty {
                let (augmentedUSDCInputs, augmentedUSDCTargets) = augmentWithNoise(inputs: usdcInputs, targets: usdcTargets, sigma: 0.001, multiplier: 2)
                try await engine.trainPriceModel(trainingData: augmentedUSDCInputs, targets: augmentedUSDCTargets, epochs: 20, coinSymbol: "USDC")
                logger.info(component: "MLPatternEngineFactory", event: "USDC transfer learning completed", data: ["samples": String(augmentedUSDCInputs.count)])
            }
        } else {
            logger.warn(component: "MLPatternEngineFactory", event: "Insufficient USDC data for transfer learning", data: ["count": String(usdcData.count)])
        }

        logger.info(component: "MLPatternEngineFactory", event: "Enhanced MLX model training completed", data: [
            "total_samples": String(trainingBatch.count),
            "coins_processed": String(topCoins.count)
        ])
    }
    #endif

    private func convertFeaturesToTrainingVector(_ features: [String: Double]) -> [Double] {
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

}
