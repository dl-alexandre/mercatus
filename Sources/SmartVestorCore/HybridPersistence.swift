import Foundation
import Utils

public class HybridPersistence: PersistenceProtocol {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence?
    private let useTigerBeetleForTransactions: Bool
    private let useTigerBeetleForBalances: Bool
    private let logger: StructuredLogger
    private let featureFlags: FeatureFlagManager?
    private let rbac: LedgerAccessControl?

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence?,
        useTigerBeetleForTransactions: Bool = true,
        useTigerBeetleForBalances: Bool = true,
        logger: StructuredLogger = StructuredLogger(),
        featureFlags: FeatureFlagManager? = nil,
        rbac: LedgerAccessControl? = nil
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.useTigerBeetleForTransactions = useTigerBeetleForTransactions
        self.useTigerBeetleForBalances = useTigerBeetleForBalances
        self.logger = logger
        self.featureFlags = featureFlags
        self.rbac = rbac
    }

    public func initialize() throws {
        try sqlitePersistence.initialize()
    }

    public func migrate() throws {
        try sqlitePersistence.migrate()
    }

    public func getCurrentVersion() throws -> Int {
        return try sqlitePersistence.getCurrentVersion()
    }

    public func setVersion(_ version: Int) throws {
        try sqlitePersistence.setVersion(version)
    }

    public func saveAccount(_ account: Holding) throws {
        if useTigerBeetleForBalances, let tbPersistence = tigerBeetlePersistence {
            try tbPersistence.saveAccount(account)
            try sqlitePersistence.saveAccount(account)
        } else {
            try sqlitePersistence.saveAccount(account)
        }
    }

    public func getAccount(exchange: String, asset: String) throws -> Holding? {
        let shouldReadFromTB: Bool

        if let flags = featureFlags {
            shouldReadFromTB = (try? Task<Bool, Error>.runBlocking(operation: {
                await flags.isEnabled(.readFromTigerBeetle)
            })) ?? false
        } else {
            shouldReadFromTB = false
        }

        if useTigerBeetleForBalances && shouldReadFromTB, let tbPersistence = tigerBeetlePersistence {
            if let account = try tbPersistence.getAccount(exchange: exchange, asset: asset) {
                return account
            }
        }
        return try sqlitePersistence.getAccount(exchange: exchange, asset: asset)
    }

    public func getAllAccounts() throws -> [Holding] {
        if useTigerBeetleForBalances, let tbPersistence = tigerBeetlePersistence {
            return try tbPersistence.getAllAccounts()
        }
        return try sqlitePersistence.getAllAccounts()
    }

    public func updateAccountBalance(exchange: String, asset: String, available: Double, pending: Double, staked: Double) throws {
        if useTigerBeetleForBalances, let tbPersistence = tigerBeetlePersistence {
            try tbPersistence.updateAccountBalance(exchange: exchange, asset: asset, available: available, pending: pending, staked: staked)
            try sqlitePersistence.updateAccountBalance(exchange: exchange, asset: asset, available: available, pending: pending, staked: staked)
        } else {
            try sqlitePersistence.updateAccountBalance(exchange: exchange, asset: asset, available: available, pending: pending, staked: staked)
        }
    }

    public func saveTransaction(_ transaction: InvestmentTransaction) throws {
        if let rbac = rbac {
            try tigerBeetlePersistence?.checkWritePermission(component: "HybridPersistence", rbac: rbac)
        }

        let shouldMirror: Bool
        let shouldDisableSQLite: Bool

        if let flags = featureFlags {
            shouldMirror = (try? Task<Bool, Error>.runBlocking(operation: {
                await flags.isEnabled(.mirrorWrites)
            })) ?? false
            shouldDisableSQLite = (try? Task<Bool, Error>.runBlocking(operation: {
                await flags.isEnabled(.disableSQLiteWrites)
            })) ?? false
        } else {
            shouldMirror = false
            shouldDisableSQLite = false
        }

        if useTigerBeetleForTransactions, let tbPersistence = tigerBeetlePersistence {
            try tbPersistence.saveTransaction(transaction)
            if !shouldDisableSQLite && shouldMirror {
                try sqlitePersistence.saveTransaction(transaction)
            }
        } else {
            try sqlitePersistence.saveTransaction(transaction)
        }
    }

    public func getTransactions(exchange: String?, asset: String?, type: TransactionType?, limit: Int?) throws -> [InvestmentTransaction] {
        if useTigerBeetleForTransactions, let tbPersistence = tigerBeetlePersistence {
            let tbTransactions = try tbPersistence.getTransactions(exchange: exchange, asset: asset, type: type, limit: limit)
            if !tbTransactions.isEmpty {
                return tbTransactions
            }
        }
        return try sqlitePersistence.getTransactions(exchange: exchange, asset: asset, type: type, limit: limit)
    }

    public func getTransaction(by idempotencyKey: String) throws -> InvestmentTransaction? {
        if useTigerBeetleForTransactions, let tbPersistence = tigerBeetlePersistence {
            if let transaction = try tbPersistence.getTransaction(by: idempotencyKey) {
                return transaction
            }
        }
        return try sqlitePersistence.getTransaction(by: idempotencyKey)
    }

    public func saveAllocationPlan(_ plan: AllocationPlan) throws {
        try sqlitePersistence.saveAllocationPlan(plan)
    }

    public func getAllocationPlans(limit: Int?) throws -> [AllocationPlan] {
        return try sqlitePersistence.getAllocationPlans(limit: limit)
    }

    public func getLatestAllocationPlan() throws -> AllocationPlan? {
        return try sqlitePersistence.getLatestAllocationPlan()
    }

    public func saveAuditEntry(_ entry: AuditEntry) throws {
        try sqlitePersistence.saveAuditEntry(entry)
    }

    public func getAuditEntries(component: String?, limit: Int?) throws -> [AuditEntry] {
        return try sqlitePersistence.getAuditEntries(component: component, limit: limit)
    }

    public func beginTransaction() throws {
        try sqlitePersistence.beginTransaction()
    }

    public func commitTransaction() throws {
        try sqlitePersistence.commitTransaction()
    }

    public func rollbackTransaction() throws {
        try sqlitePersistence.rollbackTransaction()
    }
}
