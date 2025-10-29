import Testing
import Foundation
@testable import SmartVestor
import Utils
import MLPatternEngine

@Suite(.serialized)
struct SmartVestorTests {

    @Test("Configuration Management")
    func testConfigurationManagement() async throws {
        let config = SmartVestorConfig()

        #expect(config.baseAllocation.btc == 0.4)
        #expect(config.baseAllocation.eth == 0.3)
        #expect(config.baseAllocation.altcoins == 0.3)
        #expect(config.feeCap == 0.003)
        #expect(config.depositAmount == 100.0)
        #expect(config.baseAllocation.isValid == true)
    }

    @Test("Database Schema Creation")
    func testDatabaseSchemaCreation() async throws {
        let dbPath = "/tmp/test_smartvestor_\(UUID().uuidString).db"

        // Ensure clean state - remove any existing files
        let fm = FileManager.default
        if fm.fileExists(atPath: dbPath) {
            try fm.removeItem(atPath: dbPath)
        }
        // Also remove WAL and SHM files if they exist
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"
        if fm.fileExists(atPath: walPath) {
            try fm.removeItem(atPath: walPath)
        }
        if fm.fileExists(atPath: shmPath) {
            try fm.removeItem(atPath: shmPath)
        }

        let persistence = SQLitePersistence(dbPath: dbPath)

        do {
            try persistence.initialize()

            let version = try persistence.getCurrentVersion()
            #expect(version == DatabaseSchema.version)

            // Explicitly close the connection before cleanup
            persistence.close()
        } catch {
            persistence.close()
            throw error
        }

        try fm.removeItem(atPath: dbPath)
    }

    @Test("Account Management")
    func testAccountManagement() async throws {
        let dbPath = "/tmp/test_accounts_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        // Debug: Check if database was initialized properly
        let version = try persistence.getCurrentVersion()
        #expect(version == DatabaseSchema.version)

        let account = Holding(
            exchange: "kraken",
            asset: "USDC",
            available: 100.0,
            pending: 10.0,
            staked: 5.0
        )

        // Debug: Check if account has a valid UUID
        #expect(account.id.uuidString.count > 0)

        try persistence.saveAccount(account)

        // Keep persistence alive to prevent deinit from closing the connection
        let retrievedAccount = try persistence.getAccount(exchange: "kraken", asset: "USDC")
        #expect(retrievedAccount != nil)
        #expect(retrievedAccount?.available == 100.0)
        #expect(retrievedAccount?.pending == 10.0)
        #expect(retrievedAccount?.staked == 5.0)

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Transaction Management")
    func testTransactionManagement() async throws {
        let dbPath = "/tmp/test_transactions_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let transaction = InvestmentTransaction(
            type: .deposit,
            exchange: "kraken",
            asset: "USDC",
            quantity: 100.0,
            price: 1.0,
            fee: 0.0,
            metadata: ["test": "value"]
        )

        try persistence.saveTransaction(transaction)

        let transactions = try persistence.getTransactions(exchange: "kraken", asset: "USDC")
        #expect(transactions.count == 1)
        #expect(transactions.first?.type == .deposit)
        #expect(transactions.first?.quantity == 100.0)

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Allocation Plan Creation")
    func testAllocationPlanCreation() async throws {
        let dbPath = "/tmp/test_allocation_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let config = SmartVestorConfig()
        let allocationManager = AllocationManager(config: config, persistence: persistence)

        let plan = try await allocationManager.createAllocationPlan(amount: 100.0)

        #expect(plan.baseAllocation.btc == 0.4)
        #expect(plan.baseAllocation.eth == 0.3)
        #expect(plan.baseAllocation.altcoins == 0.3)
        #expect(plan.adjustedAllocation.btc == 0.4)
        #expect(plan.adjustedAllocation.eth == 0.3)

        try persistence.saveAllocationPlan(plan)

        let retrievedPlan = try persistence.getLatestAllocationPlan()
        #expect(retrievedPlan != nil)
        #expect(retrievedPlan?.id == plan.id)

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Deposit Validation")
    func testDepositValidation() async throws {
        _ = SmartVestorConfig()
        let dbPath = "/tmp/test_deposits.db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let depositMonitor = MockDepositMonitor()

        let validDeposit = DepositDetection(
            exchange: "kraken",
            asset: "USDC",
            amount: 100.0,
            network: "USDC-ETH"
        )

        let validation = try await depositMonitor.validateDeposit(validDeposit)
        #expect(validation.isValid == true)

        let invalidDeposit = DepositDetection(
            exchange: "kraken",
            asset: "USDC",
            amount: 50.0,
            network: "USDC-ETH"
        )

        let invalidValidation = try await depositMonitor.validateDeposit(invalidDeposit)
        #expect(invalidValidation.isValid == false)

        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Cross Exchange Analysis")
    func testCrossExchangeAnalysis() async throws {
        _ = SmartVestorConfig()
        let analyzer = MockCrossExchangeAnalyzer()

        let spreads = try await analyzer.analyzeSpreads(for: ["BTC", "ETH"])

        #expect(spreads.count == 2)
        #expect(spreads["BTC"] != nil)
        #expect(spreads["ETH"] != nil)
        #expect(spreads["BTC"]?.meetsFeeCap == true)
        #expect(spreads["ETH"]?.meetsFeeCap == true)
    }

    @Test("Market Condition Analysis")
    func testMarketConditionAnalysis() async throws {
        _ = SmartVestorConfig()
        let dbPath = "/tmp/test_market.db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let executionEngine = MockExecutionEngine()
        let condition = try await executionEngine.analyzeMarketConditions()

        #expect(condition.rsi >= 0 && condition.rsi <= 100)
        #expect(condition.priceVsMA30 > 0)

        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Execution Engine")
    func testExecutionEngine() async throws {
        _ = SmartVestorConfig()
        let dbPath = "/tmp/test_execution.db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let executionEngine = MockExecutionEngine()

        let result = try await executionEngine.placeMakerOrder(
            asset: "BTC",
            quantity: 0.001,
            exchange: "kraken",
            dryRun: true
        )

        #expect(result.success == true)
        #expect(result.asset == "BTC")
        #expect(result.quantity == 0.001)
        #expect(result.exchange == "kraken")

        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Investment Scheduler")
    func testInvestmentScheduler() async throws {
        let config = SmartVestorConfig()
        let dbPath = "/tmp/test_scheduler_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let depositMonitor = MockDepositMonitor()
        let allocationManager = MockAllocationManager()
        let executionEngine = MockExecutionEngine()
        let crossExchangeAnalyzer = MockCrossExchangeAnalyzer()

        let scheduler = InvestmentScheduler(
            config: config,
            persistence: persistence,
            depositMonitor: depositMonitor,
            allocationManager: allocationManager,
            executionEngine: executionEngine,
            crossExchangeAnalyzer: crossExchangeAnalyzer
        )

        try await scheduler.runInvestmentCycle()

        let auditEntries = try persistence.getAuditEntries(component: "InvestmentScheduler")
        #expect(auditEntries.count >= 1)

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("CLI Commands")
    func testCLICommands() async throws {
        _ = SmartVestorConfig()
        let dbPath = "/tmp/test_cli_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let account = Holding(
            exchange: "kraken",
            asset: "USDC",
            available: 100.0
        )
        try persistence.saveAccount(account)

        let accounts = try persistence.getAllAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.asset == "USDC")
        #expect(accounts.first?.available == 100.0)

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Error Handling")
    func testErrorHandling() async throws {
        let config = SmartVestorConfig()
        let dbPath = "/tmp/test_errors.db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let allocationManager = AllocationManager(config: config, persistence: persistence)

        do {
            let plan = try await allocationManager.createAllocationPlan(amount: -100.0)
            #expect(plan.baseAllocation.btc >= 0)
        } catch {
            #expect(error is SmartVestorError)
        }

        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Configuration Validation")
    func testConfigurationValidation() async throws {
        let validConfig = SmartVestorConfig(
            baseAllocation: BaseAllocation(btc: 0.4, eth: 0.3, altcoins: 0.3),
            feeCap: 0.003,
            depositAmount: 100.0
        )

        #expect(validConfig.baseAllocation.isValid == true)
        #expect(validConfig.feeCap <= 0.003)
        #expect(validConfig.depositAmount > 0)

        let invalidConfig = SmartVestorConfig(
            baseAllocation: BaseAllocation(btc: 0.6, eth: 0.5, altcoins: 0.3),
            feeCap: 0.003,
            depositAmount: 100.0
        )

        #expect(invalidConfig.baseAllocation.isValid == false)
    }

    @Test("Audit Trail")
    func testAuditTrail() async throws {
        let dbPath = "/tmp/test_audit_\(UUID().uuidString).db"
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let auditEntry = AuditEntry(
            component: "TestComponent",
            action: "test_action",
            details: ["key": "value"],
            hash: "test_hash"
        )

        try persistence.saveAuditEntry(auditEntry)

        let entries = try persistence.getAuditEntries(component: "TestComponent")
        #expect(entries.count == 1)
        #expect(entries.first?.component == "TestComponent")
        #expect(entries.first?.action == "test_action")
        #expect(entries.first?.details["key"] == "value")

        // Explicitly close the connection before cleanup
        persistence.close()
        try FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("Robinhood Integration - Single Coin Real ML Engine")
    func testRobinhoodSingleCoinRealMLEngine() async throws {
        let logger = StructuredLogger()
        let factory = MLPatternEngineFactory(logger: logger)
        let mlEngine = try await factory.createMLPatternEngine()
        let mlScoringEngine = MLScoringEngine(mlEngine: mlEngine, logger: logger)

        let testSymbol = "BTC"
        let coinScore = try await mlScoringEngine.scoreCoin(symbol: testSymbol)

        #expect(coinScore.symbol == testSymbol)
        #expect(coinScore.totalScore >= 0.0)
        #expect(coinScore.technicalScore >= 0.0)
        #expect(coinScore.fundamentalScore >= 0.0)
        #expect(coinScore.momentumScore >= 0.0)
        #expect(coinScore.volatilityScore >= 0.0)
        #expect(coinScore.liquidityScore >= 0.0)

        #expect(coinScore.marketCap >= 0)
        #expect(coinScore.volume24h >= 0)
        #expect(coinScore.priceChange24h.isFinite)
        #expect(coinScore.priceChange7d.isFinite)
        #expect(coinScore.priceChange30d.isFinite)

        try? await mlEngine.stop()
    }

    @Test("Robinhood Integration - Filter 42 Coins")
    func testRobinhoodIntegrationFilter42Coins() async throws {
        let logger = createTestLogger()
        let factory = MLPatternEngineFactory(
            logger: logger,
            useMLXModels: false
        )
        let mlEngine = try await factory.createMLPatternEngine()
        let mlScoringEngine = MLScoringEngine(mlEngine: mlEngine, logger: logger)

        let allCoinScores = try await mlScoringEngine.scoreAllCoins()

        #expect(allCoinScores.count > 0)
    }
}
