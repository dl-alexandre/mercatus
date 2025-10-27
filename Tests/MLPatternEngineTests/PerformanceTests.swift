import Testing
import Foundation
@testable import MLPatternEngine
@testable import MLPatternEngineAPI
@testable import Utils
@testable import SmartVestor
@testable import Core

@Suite("Performance Tests")
struct PerformanceTests {

    @Test func testPredictionLatency() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        // Measure latency over multiple requests
        var latencies: [TimeInterval] = []
        let requestCount = 100

        for _ in 0..<requestCount {
            let startTime = Date()
            _ = try await apiService.predictPrice(
                request: request,
                authToken: authToken
            )
            let latency = Date().timeIntervalSince(startTime)
            latencies.append(latency)
        }

        // Calculate statistics
        let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
        let p95Latency = latencies.sorted()[Int(Double(latencies.count) * 0.95)]
        let p99Latency = latencies.sorted()[Int(Double(latencies.count) * 0.99)]
        let maxLatency = latencies.max() ?? 0

        // Verify performance requirements
        #expect(averageLatency < 0.1) // Average latency < 100ms
        #expect(p95Latency < 0.2) // P95 latency < 200ms
        #expect(p99Latency < 0.5) // P99 latency < 500ms
        #expect(maxLatency < 1.0) // Max latency < 1s

    }

    @Test func testConcurrentRequestThroughput() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let concurrentRequests = 50
        let requestsPerClient = 20

        // Create concurrent clients
        let startTime = Date()

        let tasks = (0..<concurrentRequests).map { _ in
            Task {
                for _ in 0..<requestsPerClient {
                    let request = PredictionRequestDTO(
                        symbol: "BTC-USD",
                        timeHorizon: 300,
                        modelType: "PRICE_PREDICTION",
                        features: ["price": 50000.0]
                    )
                    _ = try await apiService.predictPrice(
                        request: request,
                        authToken: authToken
                    )
                }
            }
        }

        // Wait for all tasks to complete
        for task in tasks {
            try await task.value
        }

        let totalTime = Date().timeIntervalSince(startTime)
        let totalRequests = concurrentRequests * requestsPerClient
        let requestsPerSecond = Double(totalRequests) / totalTime

        // Verify throughput requirements
        #expect(requestsPerSecond > 100) // At least 100 requests per second
        #expect(totalTime < 10) // Complete within 10 seconds

    }

    @Test func testMemoryUsage() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        // Measure memory usage over time
        var memoryUsage: [Int64] = []
        let iterations = 1000

        for i in 0..<iterations {
            _ = try await apiService.predictPrice(
                request: request,
                authToken: authToken
            )

            // Sample memory usage every 100 iterations
            if i % 100 == 0 {
                let memory = getCurrentMemoryUsage()
                memoryUsage.append(memory)
            }
        }

        let averageMemory = memoryUsage.reduce(0, +) / Int64(memoryUsage.count)
        let maxMemory = memoryUsage.max() ?? 0

        // Verify memory requirements
        #expect(averageMemory < 100 * 1024 * 1024) // Average < 100MB
        #expect(maxMemory < 200 * 1024 * 1024) // Max < 200MB

    }

    @Test func testCachePerformance() async throws {
        let logger = createTestLogger()
        let cacheManager = MockCacheManager(logger: logger)

        let key = "test-key"
        let value = PredictionResponse(
            id: UUID().uuidString,
            prediction: 50000.0,
            confidence: 0.85,
            uncertainty: 0.1,
            modelVersion: "1.0.0",
            timestamp: Date()
        )

        // Test cache set performance
        let setStartTime = Date()
        for i in 0..<1000 {
            try await cacheManager.set(
                key: "\(key)-\(i)",
                value: value,
                ttl: 300
            )
        }
        let setTime = Date().timeIntervalSince(setStartTime)

        // Test cache get performance
        let getStartTime = Date()
        for i in 0..<1000 {
            _ = try await cacheManager.get(
                key: "\(key)-\(i)",
                type: PredictionResponse.self
            )
        }
        let getTime = Date().timeIntervalSince(getStartTime)

        // Verify cache performance
        #expect(setTime < 1.0) // Set 1000 items in < 1s
        #expect(getTime < 0.5) // Get 1000 items in < 0.5s

    }

    @Test func testBatchPredictionPerformance() async throws {
        let logger = createTestLogger()
        let mockMLEngine = createMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let batchSize = 100

        // Create batch requests
        let requests = (0..<batchSize).map { i in
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": Double(50000 + i)]
            )
        }

        // Measure batch prediction performance
        let startTime = Date()
        let responses = try await apiService.batchPredict(
            request: BatchPredictionRequestDTO(requests: requests),
            authToken: authToken
        )
        let totalTime = Date().timeIntervalSince(startTime)

        // Verify batch performance
        #expect(responses.count == batchSize)
        #expect(totalTime < 2.0) // Complete batch in < 2s

        let requestsPerSecond = Double(batchSize) / totalTime
        #expect(requestsPerSecond > 50) // At least 50 requests per second

    }

    @Test func testErrorRecoveryPerformance() async throws {
        let logger = createTestLogger()
        let failingMLEngine = createFailingMockMLPatternEngine(logger: logger)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: failingMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        // Measure error handling performance
        let startTime = Date()
        var errorCount = 0

        for _ in 0..<100 {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
            } catch {
                errorCount += 1
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)

        // Verify error handling performance
        #expect(errorCount == 100) // All requests should fail
        #expect(totalTime < 5.0) // Error handling should be fast

    }

    @Test func testTechnicalIndicatorsPerformance() async throws {
        let technicalIndicators = TechnicalIndicators()

        let prices = Array(0..<10000).map { Double($0) + 50000.0 + Double.random(in: 0..<1000) }

        let startTime = Date()

        let rsi = technicalIndicators.calculateRSI(prices: prices, period: 14)
        let macd = technicalIndicators.calculateMACD(prices: prices, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        let bollinger = technicalIndicators.calculateBollingerBands(prices: prices, period: 20)
        let ema = technicalIndicators.calculateEMA(prices: prices, period: 12)
        let stochastic = technicalIndicators.calculateStochastic(
            high: prices.map { $0 + 100 },
            low: prices.map { $0 - 100 },
            close: prices,
            kPeriod: 14
        )

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed < 1.0)
        #expect(rsi.count > 0)
        #expect(macd.macd.count > 0)
        #expect(bollinger.upper.count > 0)
        #expect(ema.count > 0)
        #expect(stochastic.k.count > 0)

        print("Technical Indicators Performance: \(String(format: "%.3f", elapsed))s for 10K data points")
    }

    @Test func testConcurrentCoinScoring() async throws {
        let symbols = ["BTC", "ETH", "BNB", "ADA", "SOL"]

        let concurrentStartTime = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in symbols {
                group.addTask {
                    let technicalIndicators = TechnicalIndicators()
                    let prices = Array(0..<1000).map { _ in Double.random(in: 30000...50000) }
                    _ = technicalIndicators.calculateRSI(prices: prices)
                    _ = technicalIndicators.calculateMACD(prices: prices)
                    _ = technicalIndicators.calculateBollingerBands(prices: prices)
                }
            }
        }
        let concurrentTime = Date().timeIntervalSince(concurrentStartTime)

        let sequentialStartTime = Date()
        for _ in symbols {
            let technicalIndicators = TechnicalIndicators()
            let prices = Array(0..<1000).map { _ in Double.random(in: 30000...50000) }
            _ = technicalIndicators.calculateRSI(prices: prices)
            _ = technicalIndicators.calculateMACD(prices: prices)
            _ = technicalIndicators.calculateBollingerBands(prices: prices)
        }
        let sequentialTime = Date().timeIntervalSince(sequentialStartTime)

        #expect(concurrentTime < 2.0)
        #expect(sequentialTime < 3.0)

        let speedup = sequentialTime / concurrentTime
        print("Concurrent vs Sequential: \(String(format: "%.2fx", speedup)) speedup")
        print("Concurrent: \(String(format: "%.3f", concurrentTime))s")
        print("Sequential: \(String(format: "%.3f", sequentialTime))s")
    }

    @Test func testMemoryEfficientProcessing() async throws {
        let technicalIndicators = TechnicalIndicators()

        let sizes = [1000, 5000, 10000, 50000]
        var results: [(size: Int, time: TimeInterval, memory: Int64)] = []

        for size in sizes {
            let prices = Array(0..<size).map { Double($0) + 50000.0 }

            let memoryBefore = getCurrentMemoryUsage()
            let startTime = Date()

            _ = technicalIndicators.calculateRSI(prices: prices, period: 14)
            _ = technicalIndicators.calculateMACD(prices: prices)
            _ = technicalIndicators.calculateBollingerBands(prices: prices)

            let elapsed = Date().timeIntervalSince(startTime)
            let memoryAfter = getCurrentMemoryUsage()
            let memoryDelta = memoryAfter - memoryBefore

            results.append((size, elapsed, memoryDelta))

            print("Size: \(size), Time: \(String(format: "%.3f", elapsed))s, Memory: \(String(format: "%.2f", Double(memoryDelta) / 1024.0 / 1024.0))MB")
        }

        #expect(results.allSatisfy { $0.time < 10.0 })
        #expect(results.allSatisfy { Double($0.memory) / 1024.0 / 1024.0 < 100.0 })
    }

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
}

private func createTestLogger() -> StructuredLogger {
    return StructuredLogger()
}
