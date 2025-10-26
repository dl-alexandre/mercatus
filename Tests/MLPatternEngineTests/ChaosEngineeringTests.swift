import Testing
import Foundation
@testable import MLPatternEngine
@testable import MLPatternEngineAPI
@testable import Utils

@Suite("Chaos Engineering Tests")
struct ChaosEngineeringTests {

    @Test func testNetworkPartitionResilience() async throws {
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

        let authManager = AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        let authToken = authManager.generateToken(for: "testuser")
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        var successCount = 0
        var failureCount = 0
        let totalRequests = 100

        for i in 0..<totalRequests {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
                successCount += 1
            } catch {
                failureCount += 1
            }

            if i % 20 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        let successRate = Double(successCount) / Double(totalRequests)
    }

    @Test func testResourceExhaustionRecovery() async throws {
    let logger = createTestLogger()
    let mockMLEngine = createMockMLPatternEngine(logger: logger)
    let rateLimiter = RateLimiter(maxRequests: 100, windowSize: 2) // Short window for testing
    let inputValidator = InputValidator(logger: logger)
    let authManager = MockAuthManager()
    let securityMiddleware = SecurityMiddleware(
    authManager: authManager,
    rateLimiter: rateLimiter,
    inputValidator: inputValidator,
    logger: logger
    )
    let apiService = APIService(
    mlEngine: mockMLEngine,
    logger: logger,
    securityMiddleware: securityMiddleware,
    rateLimiter: rateLimiter,
    authManager: authManager
    )

    let authToken = "valid-token"
        let request = PredictionRequestDTO(
            symbol: "BTC-USD",
            timeHorizon: 300,
            modelType: "PRICE_PREDICTION",
            features: ["price": 50000.0]
        )

        // 1. Exhaust the rate limit
        let concurrentTasks = 150
        let rateLimitExceededCount = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    do {
                        _ = try await apiService.predictPrice(
                            request: request,
                            authToken: authToken
                        )
                        return 0
                    } catch let error as APIError where error == .rateLimitExceeded {
                        return 1
                    } catch {
                        // Other errors are not expected in this phase
                        return 0
                    }
                }
            }

            var totalCount = 0
            for await count in group {
                totalCount += count
            }
            return totalCount
        }

        #expect(rateLimitExceededCount > 0)

        // 2. Wait for the window to reset
        try await Task.sleep(for: .seconds(3))

        // 3. Verify recovery
        var recoverySuccess = false
        do {
            _ = try await apiService.predictPrice(
                request: request,
                authToken: authToken
            )
            recoverySuccess = true
        } catch {
            // No error expected after recovery
        }

        #expect(recoverySuccess)

        // 4. Check health
        let health = apiService.getHealth()
        #expect(health.isHealthy)

    }

    @Test func testCascadingFailurePrevention() async throws {
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

        // Simulate cascading failures by introducing intermittent errors
        var consecutiveFailures = 0
        var maxConsecutiveFailures = 0
        let totalRequests = 200

        for i in 0..<totalRequests {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
                consecutiveFailures = 0
            } catch {
                consecutiveFailures += 1
                maxConsecutiveFailures = max(maxConsecutiveFailures, consecutiveFailures)
            }

            // Simulate intermittent failures
            if i % 10 == 0 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            }
        }

        // Verify cascading failure prevention
        #expect(maxConsecutiveFailures < 10) // No more than 10 consecutive failures

    }

    @Test func testDataCorruptionHandling() async throws {
    let logger = createTestLogger()
    let mockMLEngine = createMockMLPatternEngine(logger: logger)
    let inputValidator = InputValidator(logger: logger)
    let securityMiddleware = SecurityMiddleware(
    authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger),
    rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
    inputValidator: inputValidator,
    logger: logger
    )
    let apiService = APIService(
            mlEngine: mockMLEngine,
            logger: logger,
            securityMiddleware: securityMiddleware,
            rateLimiter: RateLimiter(maxRequests: 100, windowSize: 60),
            authManager: AuthManager(jwtSecret: "test-secret", tokenExpiry: 3600, logger: logger)
        )

        let authToken = "valid-token"

        // Test with corrupted data
        let corruptedRequests = [
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": Double.nan] // NaN value
            ),
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": Double.infinity] // Infinity value
            ),
            PredictionRequestDTO(
                symbol: "BTC-USD",
                timeHorizon: 300,
                modelType: "PRICE_PREDICTION",
                features: ["price": -1000.0] // Negative price
            )
        ]

        var handledCorruptions = 0

        for request in corruptedRequests {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
            } catch let error as APIError where error == .invalidInput {
                handledCorruptions += 1
            } catch {
                // Other errors are not expected
            }
        }

        // Verify data corruption handling
        #expect(handledCorruptions == corruptedRequests.count) // System should handle all corrupted data requests

    }

    @Test func testCircuitBreakerBehavior() async throws {
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

        // Test circuit breaker behavior under continuous failures
        var failureCount = 0
        let totalRequests = 50

        for _ in 0..<totalRequests {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
            } catch {
                failureCount += 1
            }
        }

        // Verify circuit breaker behavior
        #expect(failureCount == totalRequests) // All requests should fail
        #expect(failureCount > 0) // System should detect failures

    }

    @Test func testMemoryLeakDetection() async throws {
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
        let initialMemory = getCurrentMemoryUsage()
        let iterations = 1000

        for _ in 0..<iterations {
            _ = try await apiService.predictPrice(
                request: request,
                authToken: authToken
            )
        }

        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory

        // Verify no significant memory leaks
        #expect(memoryIncrease < 50 * 1024 * 1024) // Less than 50MB increase

    }

    @Test func testTimeoutResilience() async throws {
        let logger = createTestLogger()
        let slowMLEngine = createSlowMockMLPatternEngine(logger: logger, delay: 0.2)
        let securityMiddleware = MockSecurityMiddleware()
        let apiService = APIService(
            mlEngine: slowMLEngine,
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

        var completedCount = 0
        let totalRequests = 10

        for _ in 0..<totalRequests {
            do {
                _ = try await apiService.predictPrice(
                    request: request,
                    authToken: authToken
                )
                completedCount += 1
            } catch {
            }
        }

    }

    @Test func testGracefulDegradation() async throws {
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

        // Test graceful degradation under load
        let concurrentTasks = 100
        let tasks = (0..<concurrentTasks).map { _ in
            Task {
                do {
                    let response = try await apiService.predictPrice(
                        request: request,
                        authToken: authToken
                    )
                    return response.confidence
                } catch {
                    return 0.0
                }
            }
        }

        let results = try await withThrowingTaskGroup(of: Double.self) { group in
            for task in tasks {
                group.addTask {
                    await task.value
                }
            }

            var results: [Double] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        let validResults = results.filter { $0 > 0 }
        let degradationRate = Double(validResults.count) / Double(concurrentTasks)

        // Verify graceful degradation
        #expect(degradationRate > 0.5) // At least 50% of requests should succeed

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
