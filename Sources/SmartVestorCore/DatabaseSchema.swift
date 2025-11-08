import Foundation
import SQLite3

public struct DatabaseSchema {
    public static let version = 2

    public static let migrations: [Int: [String]] = [
        1: [
            "ALTER TABLE tx ADD COLUMN notes TEXT;"
        ]
    ]

    public static let createAccountsTable = """
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            exchange TEXT NOT NULL,
            asset TEXT NOT NULL,
            available REAL NOT NULL DEFAULT 0.0,
            pending REAL NOT NULL DEFAULT 0.0,
            staked REAL NOT NULL DEFAULT 0.0,
            updated_at INTEGER NOT NULL,
            UNIQUE(exchange, asset)
        );
    """

    public static let createTransactionsTable = """
        CREATE TABLE IF NOT EXISTS tx (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            exchange TEXT NOT NULL,
            asset TEXT NOT NULL,
            qty REAL NOT NULL,
            price REAL NOT NULL,
            fee REAL NOT NULL,
            ts INTEGER NOT NULL,
            meta_json TEXT,
            idempotency_key TEXT UNIQUE NOT NULL
        );
    """

    public static let createAllocationPlansTable = """
        CREATE TABLE IF NOT EXISTS alloc_plans (
            id TEXT PRIMARY KEY,
            ts INTEGER NOT NULL,
            base_json TEXT NOT NULL,
            adjusted_json TEXT NOT NULL,
            rationale TEXT NOT NULL,
            volatility_adjustment_json TEXT,
            altcoin_rotation_json TEXT
        );
    """

    public static let createAuditTable = """
        CREATE TABLE IF NOT EXISTS audit (
            id TEXT PRIMARY KEY,
            ts INTEGER NOT NULL,
            component TEXT NOT NULL,
            action TEXT NOT NULL,
            details_json TEXT NOT NULL,
            hash TEXT NOT NULL
        );
    """

    public static let createSchemaVersionTable = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
    """

    public static let createIndexes = [
        "CREATE INDEX IF NOT EXISTS idx_accounts_exchange_asset ON accounts(exchange, asset);",
        "CREATE INDEX IF NOT EXISTS idx_accounts_updated_at ON accounts(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_tx_exchange_asset ON tx(exchange, asset);",
        "CREATE INDEX IF NOT EXISTS idx_tx_ts ON tx(ts);",
        "CREATE INDEX IF NOT EXISTS idx_tx_type ON tx(type);",
        "CREATE INDEX IF NOT EXISTS idx_tx_idempotency_key ON tx(idempotency_key);",
        "CREATE INDEX IF NOT EXISTS idx_alloc_plans_ts ON alloc_plans(ts);",
        "CREATE INDEX IF NOT EXISTS idx_audit_component ON audit(component);",
        "CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit(ts);"
    ]

    public static let allTables = [
        createAccountsTable,
        createTransactionsTable,
        createAllocationPlansTable,
        createAuditTable,
        createSchemaVersionTable
    ]

    public static let allStatements = allTables + createIndexes
}

public protocol PersistenceProtocol {
    func initialize() throws
    func migrate() throws
    func getCurrentVersion() throws -> Int
    func setVersion(_ version: Int) throws

    func saveAccount(_ account: Holding) throws
    func getAccount(exchange: String, asset: String) throws -> Holding?
    func getAllAccounts() throws -> [Holding]
    func updateAccountBalance(exchange: String, asset: String, available: Double, pending: Double, staked: Double) throws

    func saveTransaction(_ transaction: InvestmentTransaction) throws
    func getTransactions(exchange: String?, asset: String?, type: TransactionType?, limit: Int?) throws -> [InvestmentTransaction]
    func getTransaction(by idempotencyKey: String) throws -> InvestmentTransaction?

    func saveAllocationPlan(_ plan: AllocationPlan) throws
    func getAllocationPlans(limit: Int?) throws -> [AllocationPlan]
    func getLatestAllocationPlan() throws -> AllocationPlan?

    func saveAuditEntry(_ entry: AuditEntry) throws
    func getAuditEntries(component: String?, limit: Int?) throws -> [AuditEntry]

    func beginTransaction() throws
    func commitTransaction() throws
    func rollbackTransaction() throws
}

public class SQLitePersistence: PersistenceProtocol {
    private let dbPath: String
    private var db: OpaquePointer?

    public init(dbPath: String) {
        self.dbPath = dbPath
    }

    deinit {
        close()
    }

    public func initialize() throws {
        try open()
        try migrate()
    }

    private func open() throws {
        let result = sqlite3_open(dbPath, &db)
        guard result == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        }

        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)

        if ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] == nil {
            sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        }

        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size = -8000;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size = 134217728;", nil, nil, nil)
    }

    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public func migrate() throws {
        let currentVersion = try getCurrentVersion()

        if currentVersion == 0 {
            try createTables()
            try setVersion(DatabaseSchema.version)
        } else if currentVersion < DatabaseSchema.version {
            try performMigration(from: currentVersion, to: DatabaseSchema.version)
        }

        // Verify the migration worked
        let finalVersion = try getCurrentVersion()
        if finalVersion != DatabaseSchema.version {
            throw SmartVestorError.persistenceError("Migration failed: expected version \(DatabaseSchema.version), got \(finalVersion)")
        }
    }

    private func createTables() throws {
        for statement in DatabaseSchema.allStatements {
            try execute(statement)
        }
    }

    private func performMigration(from oldVersion: Int, to newVersion: Int) throws {
        for version in oldVersion..<newVersion {
            guard let migration = DatabaseSchema.migrations[version] else {
                throw SmartVestorError.persistenceError("No migration script found for version \(version + 1)")
            }

            try beginTransaction()
            do {
                for statement in migration {
                    try execute(statement)
                }
                try setVersion(version + 1)
                try commitTransaction()
            } catch {
                try rollbackTransaction()
                throw error
            }
        }
    }

    public func getCurrentVersion() throws -> Int {
        let tableCheckQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version';"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, tableCheckQuery, -1, &statement, nil) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            // Table doesn't exist, so it's a new database
            return 0
        }
        sqlite3_finalize(statement)

        // If table exists, get the version
        let query = "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;"

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            // Table exists but is empty, which is unexpected. Treat as a new database.
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    public func setVersion(_ version: Int) throws {
        let query = "INSERT OR REPLACE INTO schema_version (version) VALUES (?);"
        do {
            try execute(query, parameters: [version])
        } catch {
            throw SmartVestorError.persistenceError("Failed to set schema version: \(error)")
        }
    }

    public func saveAccount(_ account: Holding) throws {
        let query = """
            INSERT OR REPLACE INTO accounts (id, exchange, asset, available, pending, staked, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try execute(query, parameters: [
            account.id.uuidString,
            account.exchange,
            account.asset,
            account.available,
            account.pending,
            account.staked,
            Int(account.updatedAt.timeIntervalSince1970)
        ])
    }

    public func getAccount(exchange: String, asset: String) throws -> Holding? {
        let query = """
            SELECT id, exchange, asset, available, pending, staked, updated_at
            FROM accounts WHERE exchange = ? AND asset = ?;
        """
        return try querySingleRow(query, parameters: [exchange, asset]) { row in
            guard let idText = sqlite3_column_text(row, 0) else {
                throw SmartVestorError.persistenceError("Account ID is NULL")
            }
            let idString = String(cString: idText)
            guard let id = UUID(uuidString: idString) else {
                throw SmartVestorError.persistenceError("Invalid UUID format: '\(idString)'")
            }

            return Holding(
                id: id,
                exchange: String(cString: sqlite3_column_text(row, 1)),
                asset: String(cString: sqlite3_column_text(row, 2)),
                available: sqlite3_column_double(row, 3),
                pending: sqlite3_column_double(row, 4),
                staked: sqlite3_column_double(row, 5),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 6)))
            )
        }
    }

    public func getAllAccounts() throws -> [Holding] {
        let query = """
            SELECT id, exchange, asset, available, pending, staked, updated_at
            FROM accounts ORDER BY updated_at DESC;
        """
        return try queryRows(query) { row in
            guard let idText = sqlite3_column_text(row, 0) else {
                throw SmartVestorError.persistenceError("Account ID is NULL")
            }
            guard let id = UUID(uuidString: String(cString: idText)) else {
                throw SmartVestorError.persistenceError("Invalid UUID format: \(String(cString: idText))")
            }

            return Holding(
                id: id,
                exchange: String(cString: sqlite3_column_text(row, 1)),
                asset: String(cString: sqlite3_column_text(row, 2)),
                available: sqlite3_column_double(row, 3),
                pending: sqlite3_column_double(row, 4),
                staked: sqlite3_column_double(row, 5),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 6)))
            )
        }
    }

    public func updateAccountBalance(exchange: String, asset: String, available: Double, pending: Double, staked: Double) throws {
        let query = """
            UPDATE accounts
            SET available = ?, pending = ?, staked = ?, updated_at = ?
            WHERE exchange = ? AND asset = ?;
        """
        try execute(query, parameters: [
            available,
            pending,
            staked,
            Int(Date().timeIntervalSince1970),
            exchange,
            asset
        ])
    }

    public func saveTransaction(_ transaction: InvestmentTransaction) throws {
        let query = """
            INSERT OR REPLACE INTO tx (id, type, exchange, asset, qty, price, fee, ts, meta_json, idempotency_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let metadataJSON = try JSONSerialization.data(withJSONObject: transaction.metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"

        try execute(query, parameters: [
            transaction.id.uuidString,
            transaction.type.rawValue,
            transaction.exchange,
            transaction.asset,
            transaction.quantity,
            transaction.price,
            transaction.fee,
            Int(transaction.timestamp.timeIntervalSince1970),
            metadataString,
            transaction.idempotencyKey
        ])
    }

    public func getTransactions(exchange: String? = nil, asset: String? = nil, type: TransactionType? = nil, limit: Int? = nil) throws -> [InvestmentTransaction] {
        // Cap at 100 rows max, use smaller default to prevent memory issues
        let maxLimit = min(limit ?? 50, 100)
        var query = """
            SELECT id, type, exchange, asset, qty, price, fee, ts, meta_json, idempotency_key
            FROM tx
        """
        var conditions: [String] = []
        var parameters: [Any] = []

        if let exchange = exchange {
            conditions.append("exchange = ?")
            parameters.append(exchange)
        }
        if let asset = asset {
            conditions.append("asset = ?")
            parameters.append(asset)
        }
        if let type = type {
            conditions.append("type = ?")
            parameters.append(type.rawValue)
        }

        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }

        // Use index hint if possible - ORDER BY with indexed column should use idx_tx_ts
        query += " ORDER BY ts DESC LIMIT ?"
        parameters.append(maxLimit)

        return try queryRows(query, parameters: parameters) { row in
            let metadataData = sqlite3_column_text(row, 8)
            let metadataString = metadataData != nil ? String(cString: metadataData!) : "{}"
            let metadata = (try? JSONSerialization.jsonObject(with: metadataString.data(using: .utf8)!, options: [])) as? [String: String] ?? [:]

            guard let idText = sqlite3_column_text(row, 0) else {
                throw SmartVestorError.persistenceError("Transaction ID is NULL")
            }
            guard let id = UUID(uuidString: String(cString: idText)) else {
                throw SmartVestorError.persistenceError("Invalid UUID format: \(String(cString: idText))")
            }

            return InvestmentTransaction(
                id: id,
                type: TransactionType(rawValue: String(cString: sqlite3_column_text(row, 1)))!,
                exchange: String(cString: sqlite3_column_text(row, 2)),
                asset: String(cString: sqlite3_column_text(row, 3)),
                quantity: sqlite3_column_double(row, 4),
                price: sqlite3_column_double(row, 5),
                fee: sqlite3_column_double(row, 6),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 7))),
                metadata: metadata,
                idempotencyKey: String(cString: sqlite3_column_text(row, 9))
            )
        }
    }

    public func getTransaction(by idempotencyKey: String) throws -> InvestmentTransaction? {
        let query = """
            SELECT id, type, exchange, asset, qty, price, fee, ts, meta_json, idempotency_key
            FROM tx WHERE idempotency_key = ?;
        """
        return try querySingleRow(query, parameters: [idempotencyKey]) { row in
            let metadataData = sqlite3_column_text(row, 8)
            let metadataString = metadataData != nil ? String(cString: metadataData!) : "{}"
            let metadata = (try? JSONSerialization.jsonObject(with: metadataString.data(using: .utf8)!, options: [])) as? [String: String] ?? [:]

            guard let idText = sqlite3_column_text(row, 0) else {
                throw SmartVestorError.persistenceError("Transaction ID is NULL")
            }
            guard let id = UUID(uuidString: String(cString: idText)) else {
                throw SmartVestorError.persistenceError("Invalid UUID format: \(String(cString: idText))")
            }

            return InvestmentTransaction(
                id: id,
                type: TransactionType(rawValue: String(cString: sqlite3_column_text(row, 1)))!,
                exchange: String(cString: sqlite3_column_text(row, 2)),
                asset: String(cString: sqlite3_column_text(row, 3)),
                quantity: sqlite3_column_double(row, 4),
                price: sqlite3_column_double(row, 5),
                fee: sqlite3_column_double(row, 6),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 7))),
                metadata: metadata,
                idempotencyKey: String(cString: sqlite3_column_text(row, 9))
            )
        }
    }

    public func saveAllocationPlan(_ plan: AllocationPlan) throws {
        let query = """
            INSERT OR REPLACE INTO alloc_plans (id, ts, base_json, adjusted_json, rationale, volatility_adjustment_json, altcoin_rotation_json)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        let baseJSON = try JSONEncoder().encode(plan.baseAllocation)
        let baseString = String(data: baseJSON, encoding: .utf8) ?? "{}"

        let adjustedJSON = try JSONEncoder().encode(plan.adjustedAllocation)
        let adjustedString = String(data: adjustedJSON, encoding: .utf8) ?? "{}"

        let volatilityJSON = plan.volatilityAdjustment != nil ? try JSONEncoder().encode(plan.volatilityAdjustment!) : nil
        let volatilityString = volatilityJSON != nil ? String(data: volatilityJSON!, encoding: .utf8) : nil

        let rotationJSON = plan.altcoinRotation != nil ? try JSONEncoder().encode(plan.altcoinRotation!) : nil
        let rotationString = rotationJSON != nil ? String(data: rotationJSON!, encoding: .utf8) : nil

        try execute(query, parameters: [
            plan.id.uuidString,
            Int(plan.timestamp.timeIntervalSince1970),
            baseString,
            adjustedString,
            plan.rationale,
            volatilityString ?? "",
            rotationString ?? ""
        ])
    }

    public func getAllocationPlans(limit: Int? = nil) throws -> [AllocationPlan] {
        var query = """
            SELECT id, ts, base_json, adjusted_json, rationale, volatility_adjustment_json, altcoin_rotation_json
            FROM alloc_plans ORDER BY ts DESC
        """
        var parameters: [Any] = []

        if let limit = limit {
            query += " LIMIT ?"
            parameters.append(limit)
        }

        return try queryRows(query, parameters: parameters) { row in
            let baseData = sqlite3_column_text(row, 2)
            let baseString = String(cString: baseData!)
            let baseAllocation = try JSONDecoder().decode(BaseAllocation.self, from: baseString.data(using: .utf8)!)

            let adjustedData = sqlite3_column_text(row, 3)
            let adjustedString = String(cString: adjustedData!)
            let adjustedAllocation = try JSONDecoder().decode(AdjustedAllocation.self, from: adjustedString.data(using: .utf8)!)

            let volatilityData = sqlite3_column_text(row, 5)
            let volatilityString = String(cString: volatilityData!)
            let volatilityAdjustment = !volatilityString.isEmpty ? try JSONDecoder().decode(VolatilityAdjustment.self, from: volatilityString.data(using: .utf8)!) : nil

            let rotationData = sqlite3_column_text(row, 6)
            let rotationString = String(cString: rotationData!)
            let altcoinRotation = !rotationString.isEmpty ? try JSONDecoder().decode(AltcoinRotation.self, from: rotationString.data(using: .utf8)!) : nil

            return AllocationPlan(
                id: try { guard let idText = sqlite3_column_text(row, 0), let id = UUID(uuidString: String(cString: idText)) else { throw SmartVestorError.persistenceError("Invalid UUID format") }; return id }(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 1))),
                baseAllocation: baseAllocation,
                adjustedAllocation: adjustedAllocation,
                rationale: String(cString: sqlite3_column_text(row, 4)),
                volatilityAdjustment: volatilityAdjustment,
                altcoinRotation: altcoinRotation
            )
        }
    }

    public func getLatestAllocationPlan() throws -> AllocationPlan? {
        let query = """
            SELECT id, ts, base_json, adjusted_json, rationale, volatility_adjustment_json, altcoin_rotation_json
            FROM alloc_plans ORDER BY ts DESC LIMIT 1;
        """
        return try querySingleRow(query) { row in
            let baseData = sqlite3_column_text(row, 2)
            let baseString = String(cString: baseData!)
            let baseAllocation = try JSONDecoder().decode(BaseAllocation.self, from: baseString.data(using: .utf8)!)

            let adjustedData = sqlite3_column_text(row, 3)
            let adjustedString = String(cString: adjustedData!)
            let adjustedAllocation = try JSONDecoder().decode(AdjustedAllocation.self, from: adjustedString.data(using: .utf8)!)

            let volatilityData = sqlite3_column_text(row, 5)
            let volatilityString = String(cString: volatilityData!)
            let volatilityAdjustment = !volatilityString.isEmpty ? try JSONDecoder().decode(VolatilityAdjustment.self, from: volatilityString.data(using: .utf8)!) : nil

            let rotationData = sqlite3_column_text(row, 6)
            let rotationString = String(cString: rotationData!)
            let altcoinRotation = !rotationString.isEmpty ? try JSONDecoder().decode(AltcoinRotation.self, from: rotationString.data(using: .utf8)!) : nil

            return AllocationPlan(
                id: try { guard let idText = sqlite3_column_text(row, 0), let id = UUID(uuidString: String(cString: idText)) else { throw SmartVestorError.persistenceError("Invalid UUID format") }; return id }(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 1))),
                baseAllocation: baseAllocation,
                adjustedAllocation: adjustedAllocation,
                rationale: String(cString: sqlite3_column_text(row, 4)),
                volatilityAdjustment: volatilityAdjustment,
                altcoinRotation: altcoinRotation
            )
        }
    }

    public func saveAuditEntry(_ entry: AuditEntry) throws {
        let query = """
            INSERT INTO audit (id, ts, component, action, details_json, hash)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        let detailsJSON = try JSONSerialization.data(withJSONObject: entry.details)
        let detailsString = String(data: detailsJSON, encoding: .utf8) ?? "{}"

        try execute(query, parameters: [
            entry.id.uuidString,
            Int(entry.timestamp.timeIntervalSince1970),
            entry.component,
            entry.action,
            detailsString,
            entry.hash
        ])
    }

    public func getAuditEntries(component: String? = nil, limit: Int? = nil) throws -> [AuditEntry] {
        var query = """
            SELECT id, ts, component, action, details_json, hash
            FROM audit
        """
        var conditions: [String] = []
        var parameters: [Any] = []

        if let component = component {
            conditions.append("component = ?")
            parameters.append(component)
        }

        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }

        query += " ORDER BY ts DESC"

        if let limit = limit {
            query += " LIMIT ?"
            parameters.append(limit)
        }

        return try queryRows(query, parameters: parameters) { row in
            let detailsData = sqlite3_column_text(row, 4)
            let detailsString = String(cString: detailsData!)
            let details = (try? JSONSerialization.jsonObject(with: detailsString.data(using: .utf8)!, options: [])) as? [String: String] ?? [:]

            guard let idText = sqlite3_column_text(row, 0) else {
                throw SmartVestorError.persistenceError("Audit Entry ID is NULL")
            }
            guard let id = UUID(uuidString: String(cString: idText)) else {
                throw SmartVestorError.persistenceError("Invalid UUID format: \(String(cString: idText))")
            }

            return AuditEntry(
                id: id,
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 1))),
                component: String(cString: sqlite3_column_text(row, 2)),
                action: String(cString: sqlite3_column_text(row, 3)),
                details: details,
                hash: String(cString: sqlite3_column_text(row, 5))
            )
        }
    }

    public func beginTransaction() throws {
        try execute("BEGIN TRANSACTION;")
    }

    public func commitTransaction() throws {
        try execute("COMMIT;")
    }

    public func rollbackTransaction() throws {
        try execute("ROLLBACK;")
    }

    private func execute(_ sql: String, parameters: [Any] = []) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (index, parameter) in parameters.enumerated() {
            let sqlIndex = Int32(index + 1)
            switch parameter {
            case let string as String:
                sqlite3_bind_text(statement, sqlIndex, (string as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case let int as Int:
                sqlite3_bind_int(statement, sqlIndex, Int32(int))
            case let int64 as Int64:
                sqlite3_bind_int64(statement, sqlIndex, int64)
            case let double as Double:
                sqlite3_bind_double(statement, sqlIndex, double)
            default:
                throw SmartVestorError.persistenceError("Unsupported parameter type: \(String(describing: parameter))")
            }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SmartVestorError.persistenceError("Failed to execute statement: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func querySingleValue<T>(_ sql: String, parameters: [Any] = [], type: T.Type) throws -> T? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (index, parameter) in parameters.enumerated() {
            let sqlIndex = Int32(index + 1)
            switch parameter {
            case let string as String:
                sqlite3_bind_text(statement, sqlIndex, (string as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case let int as Int:
                sqlite3_bind_int(statement, sqlIndex, Int32(int))
            case let int64 as Int64:
                sqlite3_bind_int64(statement, sqlIndex, int64)
            case let double as Double:
                sqlite3_bind_double(statement, sqlIndex, double)
            default:
                throw SmartVestorError.persistenceError("Unsupported parameter type: \(String(describing: parameter))")
            }
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        switch type {
        case is Int.Type:
            return sqlite3_column_int(statement, 0) as? T
        case is Int64.Type:
            return sqlite3_column_int64(statement, 0) as? T
        case is Double.Type:
            return sqlite3_column_double(statement, 0) as? T
        case is String.Type:
            return String(cString: sqlite3_column_text(statement, 0)) as? T
        default:
            throw SmartVestorError.persistenceError("Unsupported return type: \(type)")
        }
    }

    private func querySingleRow<T>(_ sql: String, parameters: [Any] = [], _ rowMapper: (OpaquePointer) throws -> T) throws -> T? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (index, parameter) in parameters.enumerated() {
            let sqlIndex = Int32(index + 1)
            switch parameter {
            case let string as String:
                sqlite3_bind_text(statement, sqlIndex, (string as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case let int as Int:
                sqlite3_bind_int(statement, sqlIndex, Int32(int))
            case let int64 as Int64:
                sqlite3_bind_int64(statement, sqlIndex, int64)
            case let double as Double:
                sqlite3_bind_double(statement, sqlIndex, double)
            default:
                throw SmartVestorError.persistenceError("Unsupported parameter type: \(String(describing: parameter))")
            }
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return try rowMapper(statement!)
    }

    private func getTableRowCount(_ tableName: String) throws -> Int {
        let query = "SELECT COUNT(*) FROM \(tableName);"
        return try querySingleRow(query, parameters: []) { row in
            return Int(sqlite3_column_int64(row, 0))
        } ?? 0
    }

    private func queryRows<T>(_ sql: String, parameters: [Any] = [], _ rowMapper: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            let errorCode = sqlite3_extended_errcode(db)

            if prepareResult == SQLITE_NOMEM || errorCode == SQLITE_NOMEM {
                let tableCount = try? getTableRowCount("tx")
                let errorDetails = tableCount.map { " (table has ~\($0) rows)" } ?? ""
                throw SmartVestorError.persistenceError("Failed to prepare statement: out of memory\(errorDetails). Try reducing the query limit or cleaning up old transactions.")
            }

            throw SmartVestorError.persistenceError("Failed to prepare statement: \(errorMsg) (code: \(errorCode))")
        }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (index, parameter) in parameters.enumerated() {
            let sqlIndex = Int32(index + 1)
            switch parameter {
            case let string as String:
                sqlite3_bind_text(statement, sqlIndex, (string as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case let int as Int:
                sqlite3_bind_int(statement, sqlIndex, Int32(int))
            case let int64 as Int64:
                sqlite3_bind_int64(statement, sqlIndex, int64)
            case let double as Double:
                sqlite3_bind_double(statement, sqlIndex, double)
            default:
                throw SmartVestorError.persistenceError("Unsupported parameter type: \(String(describing: parameter))")
            }
        }

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(try rowMapper(statement!))
        }

        return results
    }
}
