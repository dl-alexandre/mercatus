import Foundation
import SQLite3
import Utils

public actor SQLiteTimeSeriesDatabase: DatabaseProtocol {
    public enum Location: Equatable {
        case inMemory
        case file(URL)
    }

    public enum SQLiteDatabaseError: Error, LocalizedError, Equatable {
        case openDatabase(String)
        case prepareStatement(String)
        case step(Int32, String)
        case execute(String, String)
        case fileSystem(String)
        case unexpected(String)

        public var errorDescription: String? {
            switch self {
            case .openDatabase(let message):
                return "Failed to open SQLite database: \(message)"
            case .prepareStatement(let message):
                return "Failed to prepare SQLite statement: \(message)"
            case .step(let code, let message):
                return "SQLite step failed (\(code)): \(message)"
            case .execute(let statement, let message):
                return "SQLite execute failed for '\(statement)': \(message)"
            case .fileSystem(let message):
                return "File system error: \(message)"
            case .unexpected(let message):
                return "Unexpected SQLite error: \(message)"
            }
        }
    }

    private let logger: StructuredLogger
    private let location: Location

    nonisolated(unsafe) private var db: OpaquePointer?
    private let jsonEncoder: JSONEncoder

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let dayInterval: TimeInterval = 86_400

    public init(location: Location? = nil, logger: StructuredLogger) throws {
        self.logger = logger
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .secondsSince1970

        let resolvedLocation: Location
        if let location {
            resolvedLocation = location
        } else {
            resolvedLocation = .file(try Self.defaultStoreURL())
        }
        self.location = resolvedLocation

        if case .file(let url) = resolvedLocation {
            logger.debug(component: "SQLiteTimeSeriesDatabase", event: "Database location", data: ["path": url.path])
        }

        var databasePointer: OpaquePointer?
        let path: String

        switch resolvedLocation {
        case .inMemory:
            path = ":memory:"
        case .file(let url):
            let directory = url.deletingLastPathComponent()
            do {
                let fm = FileManager.default
                if !fm.fileExists(atPath: directory.path) {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                }
            } catch {
                throw SQLiteDatabaseError.fileSystem("Failed to create directory \(directory.path): \(error)")
            }
            path = url.path
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &databasePointer, flags, nil)
        guard result == SQLITE_OK, let dbPointer = databasePointer else {
            let message = databasePointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(databasePointer)
            throw SQLiteDatabaseError.openDatabase(message)
        }

        self.db = dbPointer

        // Configure database synchronously in init
        try Self.configureDatabaseSync(db: dbPointer)
        try Self.createSchemaIfNeededSync(db: dbPointer)

        logger.info(
            component: "SQLiteTimeSeriesDatabase",
            event: "SQLite database opened",
            data: [
                "path": path,
                "location": Self.locationDescriptionSync(location: resolvedLocation)
            ]
        )
    }

    nonisolated deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    public func createTables() async throws {
        try createSchemaIfNeeded()
    }

    public func insertMarketData(_ dataPoints: [MarketDataPoint]) async throws {
        guard !dataPoints.isEmpty else { return }

        let batchSize = 100
        let batches = dataPoints.chunked(into: batchSize)

        for batch in batches {
            try withTransaction {
                let sql = """
                INSERT OR REPLACE INTO market_data(symbol, exchange, timestamp, open, high, low, close, volume)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?);
                """

                let statement = try prepareStatement(sql: sql)
                defer { sqlite3_finalize(statement) }

                for point in batch {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)

                    try bindText(point.symbol, to: statement, index: 1)
                    try bindText(point.exchange, to: statement, index: 2)
                    sqlite3_bind_double(statement, 3, point.timestamp.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 4, point.open)
                    sqlite3_bind_double(statement, 5, point.high)
                    sqlite3_bind_double(statement, 6, point.low)
                    sqlite3_bind_double(statement, 7, point.close)
                    sqlite3_bind_double(statement, 8, point.volume)

                    let stepResult = sqlite3_step(statement)
                    guard stepResult == SQLITE_DONE else {
                        throw SQLiteDatabaseError.step(stepResult, currentErrorMessage())
                    }
                }
            }
        }

        logger.debug(
            component: "SQLiteTimeSeriesDatabase",
            event: "Inserted market data batch",
            data: [
                "count": "\(dataPoints.count)"
            ]
        )
    }

    public func getMarketData(symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint] {
        let sql = """
        SELECT symbol, exchange, timestamp, open, high, low, close, volume
        FROM market_data
        WHERE symbol = ? AND timestamp BETWEEN ? AND ?
        ORDER BY timestamp ASC;
        """

        let statement = try prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }

        try bindText(symbol, to: statement, index: 1)
        sqlite3_bind_double(statement, 2, from.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, to.timeIntervalSince1970)

        var results: [MarketDataPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(mapMarketDataPoint(statement: statement))
        }

        return results
    }

    public func getLatestMarketData(symbol: String, limit: Int) async throws -> [MarketDataPoint] {
        let sql = """
        SELECT symbol, exchange, timestamp, open, high, low, close, volume
        FROM market_data
        WHERE symbol = ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        let statement = try prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }

        try bindText(symbol, to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [MarketDataPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(mapMarketDataPoint(statement: statement))
        }

        return results
    }

    public func getMarketDataBatch(symbols: [String], from: Date, to: Date) async throws -> [String: [MarketDataPoint]] {
        guard !symbols.isEmpty else { return [:] }

        let placeholders = symbols.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT symbol, exchange, timestamp, open, high, low, close, volume
        FROM market_data
        WHERE symbol IN (\(placeholders)) AND timestamp BETWEEN ? AND ?
        ORDER BY symbol, timestamp ASC;
        """

        let statement = try prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }

        for (index, symbol) in symbols.enumerated() {
            try bindText(symbol, to: statement, index: Int32(index + 1))
        }
        sqlite3_bind_double(statement, Int32(symbols.count + 1), from.timeIntervalSince1970)
        sqlite3_bind_double(statement, Int32(symbols.count + 2), to.timeIntervalSince1970)

        var results: [String: [MarketDataPoint]] = [:]
        for symbol in symbols {
            results[symbol] = []
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let point = mapMarketDataPoint(statement: statement)
            results[point.symbol, default: []].append(point)
        }

        return results
    }

    public func archiveOldMarketData(olderThan cutoff: Date) async throws {
        let cutoffInterval = cutoff.timeIntervalSince1970

        let sql = """
        SELECT symbol, exchange, timestamp, open, high, low, close, volume
        FROM market_data
        WHERE timestamp < ?
        ORDER BY symbol, exchange, timestamp ASC;
        """

        let statement = try prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoffInterval)

        var buckets: [ArchiveKey: ArchiveChunk] = [:]
        var totalRows = 0

        while sqlite3_step(statement) == SQLITE_ROW {
            let dataPoint = mapMarketDataPoint(statement: statement)
            let dayStart = floor(dataPoint.timestamp.timeIntervalSince1970 / dayInterval) * dayInterval
            let key = ArchiveKey(symbol: dataPoint.symbol, exchange: dataPoint.exchange, dayStart: dayStart)

            var chunk = buckets[key] ?? ArchiveChunk(symbol: dataPoint.symbol, exchange: dataPoint.exchange, dayStart: Date(timeIntervalSince1970: dayStart))
            chunk.append(dataPoint)
            buckets[key] = chunk
            totalRows += 1
        }

        guard !buckets.isEmpty else {
            logger.debug(
                component: "SQLiteTimeSeriesDatabase",
                event: "No market data to archive",
                data: [
                    "cutoff": "\(cutoffInterval)"
                ]
            )
            return
        }

        let insertSQL = """
        INSERT INTO archived_market_data(symbol, exchange, day_start, day_end, row_count, compression, payload, created_at)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?);
        """

        try withTransaction {
            let insertStatement = try prepareStatement(sql: insertSQL)
            defer { sqlite3_finalize(insertStatement) }

            for chunk in buckets.values {
                let jsonData = try jsonEncoder.encode(chunk.dataPoints)
                let compressedData = try (jsonData as NSData).compressed(using: .zlib) as Data

                sqlite3_reset(insertStatement)
                sqlite3_clear_bindings(insertStatement)

                try bindText(chunk.symbol, to: insertStatement, index: 1)
                try bindText(chunk.exchange, to: insertStatement, index: 2)
                sqlite3_bind_double(insertStatement, 3, chunk.dayStart.timeIntervalSince1970)
                sqlite3_bind_double(insertStatement, 4, chunk.dayEnd.timeIntervalSince1970)
                sqlite3_bind_int(insertStatement, 5, Int32(chunk.dataPoints.count))
                try bindText("zlib", to: insertStatement, index: 6)
                try bindBlob(compressedData, to: insertStatement, index: 7)
                sqlite3_bind_double(insertStatement, 8, Date().timeIntervalSince1970)

                let stepResult = sqlite3_step(insertStatement)
                guard stepResult == SQLITE_DONE else {
                    throw SQLiteDatabaseError.step(stepResult, currentErrorMessage())
                }
            }
        }

        logger.info(
            component: "SQLiteTimeSeriesDatabase",
            event: "Archived historical market data",
            data: [
                "cutoff": "\(cutoffInterval)",
                "rows": "\(totalRows)",
                "archives": "\(buckets.count)"
            ]
        )
    }

    public func deleteOldMarketData(olderThan cutoff: Date) async throws {
        try withTransaction {
            let sql = "DELETE FROM market_data WHERE timestamp < ?;"
            let statement = try prepareStatement(sql: sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)

            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_DONE else {
                throw SQLiteDatabaseError.step(stepResult, currentErrorMessage())
            }
        }

        logger.info(
            component: "SQLiteTimeSeriesDatabase",
            event: "Deleted historical market data",
            data: [
                "cutoff": "\(cutoff.timeIntervalSince1970)"
            ]
        )
    }

    // MARK: - Private helpers

    private func configureDatabase() throws {
        try execute(sql: "PRAGMA journal_mode=WAL;")
        try execute(sql: "PRAGMA synchronous=NORMAL;")
        try execute(sql: "PRAGMA temp_store=MEMORY;")
        try execute(sql: "PRAGMA cache_size=-8000;") // Approximately 8MB cache
        try execute(sql: "PRAGMA mmap_size=134217728;") // 128MB memory mapped I/O
    }

    private static func configureDatabaseSync(db: OpaquePointer?) throws {
        try executeSync(db: db, sql: "PRAGMA journal_mode=WAL;")
        try executeSync(db: db, sql: "PRAGMA synchronous=NORMAL;")
        try executeSync(db: db, sql: "PRAGMA temp_store=MEMORY;")
        try executeSync(db: db, sql: "PRAGMA cache_size=-8000;") // Approximately 8MB cache
        try executeSync(db: db, sql: "PRAGMA mmap_size=134217728;") // 128MB memory mapped I/O
    }

    private func createSchemaIfNeeded() throws {
        let createMarketDataSQL = """
        CREATE TABLE IF NOT EXISTS market_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            exchange TEXT NOT NULL,
            timestamp REAL NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            created_at REAL NOT NULL DEFAULT (strftime('%s', 'now')),
            UNIQUE(symbol, timestamp)
        );
        """

        let createMarketIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_market_data_symbol_time
        ON market_data(symbol, timestamp);
        """

        let createMarketTimestampDescIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_market_data_timestamp_desc
        ON market_data(timestamp DESC);
        """

        let createArchiveSQL = """
        CREATE TABLE IF NOT EXISTS archived_market_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            exchange TEXT NOT NULL,
            day_start REAL NOT NULL,
            day_end REAL NOT NULL,
            row_count INTEGER NOT NULL,
            compression TEXT NOT NULL,
            payload BLOB NOT NULL,
            created_at REAL NOT NULL
        );
        """

        let createDetectedPatternsSQL = """
        CREATE TABLE IF NOT EXISTS detected_patterns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern_id TEXT NOT NULL UNIQUE,
            pattern_type TEXT NOT NULL,
            symbol TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            confidence REAL NOT NULL,
            completion_score REAL NOT NULL,
            price_target REAL,
            stop_loss REAL,
            market_conditions TEXT,
            created_at REAL NOT NULL
        );
        """

        let createPatternIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_symbol_type
        ON detected_patterns(symbol, pattern_type);
        """

        let createPatternTimeIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_time
        ON detected_patterns(start_time, end_time);
        """

        let createPatternConfidenceIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_confidence
        ON detected_patterns(confidence DESC);
        """

        try execute(sql: createMarketDataSQL)
        try execute(sql: createMarketIndexSQL)
        try execute(sql: createMarketTimestampDescIndexSQL)
        try execute(sql: createArchiveSQL)
        try execute(sql: createDetectedPatternsSQL)
        try execute(sql: createPatternIndexSQL)
        try execute(sql: createPatternTimeIndexSQL)
        try execute(sql: createPatternConfidenceIndexSQL)
    }

    private static func createSchemaIfNeededSync(db: OpaquePointer?) throws {
        let createMarketDataSQL = """
        CREATE TABLE IF NOT EXISTS market_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            exchange TEXT NOT NULL,
            timestamp REAL NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL
        );
        """

        let createMarketIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_market_data_symbol_time
        ON market_data(symbol, timestamp);
        """

        let createMarketTimestampDescIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_market_data_timestamp_desc
        ON market_data(timestamp DESC);
        """

        let createArchiveSQL = """
        CREATE TABLE IF NOT EXISTS archived_market_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            symbol TEXT NOT NULL,
            exchange TEXT NOT NULL,
            day_start REAL NOT NULL,
            day_end REAL NOT NULL,
            row_count INTEGER NOT NULL,
            compression TEXT NOT NULL,
            payload BLOB NOT NULL,
            created_at REAL NOT NULL
        );
        """

        let createDetectedPatternsSQL = """
        CREATE TABLE IF NOT EXISTS detected_patterns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern_id TEXT NOT NULL UNIQUE,
            pattern_type TEXT NOT NULL,
            symbol TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            confidence REAL NOT NULL,
            completion_score REAL NOT NULL,
            price_target REAL,
            stop_loss REAL,
            market_conditions TEXT,
            created_at REAL NOT NULL
        );
        """

        let createPatternIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_symbol_type
        ON detected_patterns(symbol, pattern_type);
        """

        let createPatternTimeIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_time
        ON detected_patterns(start_time, end_time);
        """

        let createPatternConfidenceIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_detected_patterns_confidence
        ON detected_patterns(confidence DESC);
        """

        try executeSync(db: db, sql: createMarketDataSQL)
        try executeSync(db: db, sql: createMarketIndexSQL)
        try executeSync(db: db, sql: createMarketTimestampDescIndexSQL)
        try executeSync(db: db, sql: createArchiveSQL)
        try executeSync(db: db, sql: createDetectedPatternsSQL)
        try executeSync(db: db, sql: createPatternIndexSQL)
        try executeSync(db: db, sql: createPatternTimeIndexSQL)
        try executeSync(db: db, sql: createPatternConfidenceIndexSQL)
    }

    private func execute(sql: String) throws {
        guard let db else {
            throw SQLiteDatabaseError.unexpected("Database connection not initialized")
        }

        var errorMessage: UnsafeMutablePointer<Int8>? = nil
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw SQLiteDatabaseError.execute(sql, message)
        }
    }

    private static func executeSync(db: OpaquePointer?, sql: String) throws {
        guard let db else {
            throw SQLiteDatabaseError.unexpected("Database connection not initialized")
        }

        var errorMessage: UnsafeMutablePointer<Int8>? = nil
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw SQLiteDatabaseError.execute(sql, message)
        }
    }

    private func prepareStatement(sql: String) throws -> OpaquePointer? {
        guard let db else {
            throw SQLiteDatabaseError.unexpected("Database connection not initialized")
        }

        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let preparedStatement = statement else {
            throw SQLiteDatabaseError.prepareStatement(currentErrorMessage())
        }

        return preparedStatement
    }

    private func withTransaction(_ block: () throws -> Void) throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        var shouldRollback = true

        do {
            try block()
            try execute(sql: "COMMIT;")
            shouldRollback = false
        } catch {
            if shouldRollback {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
            throw error
        }
    }

    private func mapMarketDataPoint(statement: OpaquePointer?) -> MarketDataPoint {
        let symbol = String(cString: sqlite3_column_text(statement, 0))
        let exchange = String(cString: sqlite3_column_text(statement, 1))
        let timestamp = sqlite3_column_double(statement, 2)
        let open = sqlite3_column_double(statement, 3)
        let high = sqlite3_column_double(statement, 4)
        let low = sqlite3_column_double(statement, 5)
        let close = sqlite3_column_double(statement, 6)
        let volume = sqlite3_column_double(statement, 7)

        return MarketDataPoint(
            timestamp: Date(timeIntervalSince1970: timestamp),
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            exchange: exchange
        )
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        guard result == SQLITE_OK else {
            throw SQLiteDatabaseError.step(result, currentErrorMessage())
        }
    }

    private func bindBlob(_ data: Data, to statement: OpaquePointer?, index: Int32) throws {
        let result = data.withUnsafeBytes { bytes -> Int32 in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw SQLiteDatabaseError.step(result, currentErrorMessage())
        }
    }

    private func currentErrorMessage() -> String {
        guard let db else { return "database pointer nil" }
        guard let messagePointer = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: messagePointer)
    }

    private func locationDescription(location: Location) -> String {
        switch location {
        case .inMemory:
            return "in-memory"
        case .file(let url):
            return url.path
        }
    }

    private static func locationDescriptionSync(location: Location) -> String {
        switch location {
        case .inMemory:
            return "in-memory"
        case .file(let url):
            return url.path
        }
    }

    public func archivedEntryCount() async throws -> Int {
        let sql = "SELECT COUNT(*) FROM archived_market_data;"
        let statement = try prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteDatabaseError.unexpected("Failed to read archive count: \(currentErrorMessage())")
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Archive helpers

    private struct ArchiveKey: Hashable {
        let symbol: String
        let exchange: String
        let dayStart: TimeInterval
    }

    private struct ArchiveChunk {
        let symbol: String
        let exchange: String
        let dayStart: Date
        private(set) var dayEnd: Date
        private(set) var dataPoints: [MarketDataPoint]

        init(symbol: String, exchange: String, dayStart: Date) {
            self.symbol = symbol
            self.exchange = exchange
            self.dayStart = dayStart
            self.dayEnd = dayStart
            self.dataPoints = []
        }

        mutating func append(_ dataPoint: MarketDataPoint) {
            dataPoints.append(dataPoint)
            if dataPoint.timestamp > dayEnd {
                dayEnd = dataPoint.timestamp
            }
        }
    }

    private static func defaultStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportDirectories = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let baseDirectory = appSupportDirectories.first else {
            throw SQLiteDatabaseError.fileSystem("Unable to locate application support directory")
        }

        let directory = baseDirectory.appendingPathComponent("MLPatternEngine", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("time_series.sqlite3", isDirectory: false)
    }

    public func executeQuery(_ query: String, parameters: [any Sendable]) async throws -> [[String: any Sendable]] {
        guard db != nil else {
            throw SQLiteDatabaseError.unexpected("Database connection not initialized")
        }

        let statement = try prepareStatement(sql: query)
        defer { sqlite3_finalize(statement) }

        for (index, parameter) in parameters.enumerated() {
            let paramIndex = Int32(index + 1)

            switch parameter {
            case let stringValue as String:
                try bindText(stringValue, to: statement, index: paramIndex)
            case let doubleValue as Double:
                sqlite3_bind_double(statement, paramIndex, doubleValue)
            case let intValue as Int:
                sqlite3_bind_int(statement, paramIndex, Int32(intValue))
            case let int32Value as Int32:
                sqlite3_bind_int(statement, paramIndex, int32Value)
            case let dataValue as Data:
                try bindBlob(dataValue, to: statement, index: paramIndex)
            default:
                throw SQLiteDatabaseError.unexpected("Unsupported parameter type: \(type(of: parameter))")
            }
        }

        var results: [[String: any Sendable]] = []
        let columnCount = sqlite3_column_count(statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: any Sendable] = [:]

            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)

                let value: any Sendable
                switch columnType {
                case SQLITE_INTEGER:
                    value = sqlite3_column_int(statement, i)
                case SQLITE_FLOAT:
                    value = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        value = String(cString: text)
                    } else {
                        value = ""
                    }
                case SQLITE_BLOB:
                    let blobSize = sqlite3_column_bytes(statement, i)
                    if blobSize > 0, let blobData = sqlite3_column_blob(statement, i) {
                        value = Data(bytes: blobData, count: Int(blobSize))
                    } else {
                        value = Data()
                    }
                case SQLITE_NULL:
                    value = NSNull()
                default:
                    value = NSNull()
                }

                row[columnName] = value
            }

            results.append(row)
        }

        return results
    }

    public func executeUpdate(_ query: String, parameters: [any Sendable]) async throws -> Int {
        guard let db else {
            throw SQLiteDatabaseError.unexpected("Database connection not initialized")
        }

        let statement = try prepareStatement(sql: query)
        defer { sqlite3_finalize(statement) }

        for (index, parameter) in parameters.enumerated() {
            let paramIndex = Int32(index + 1)

            // Handle optionals explicitly - check if nil, bind NULL, otherwise unwrap and handle
            if let unwrapped = parameter as? Optional<Double> {
                if let value = unwrapped {
                    sqlite3_bind_double(statement, paramIndex, value)
                } else {
                    sqlite3_bind_null(statement, paramIndex)
                }
                continue
            }

            if let unwrapped = parameter as? Optional<Int> {
                if let value = unwrapped {
                    sqlite3_bind_int(statement, paramIndex, Int32(value))
                } else {
                    sqlite3_bind_null(statement, paramIndex)
                }
                continue
            }

            switch parameter {
            case let stringValue as String:
                try bindText(stringValue, to: statement, index: paramIndex)
            case let doubleValue as Double:
                sqlite3_bind_double(statement, paramIndex, doubleValue)
            case let intValue as Int:
                sqlite3_bind_int(statement, paramIndex, Int32(intValue))
            case let int32Value as Int32:
                sqlite3_bind_int(statement, paramIndex, int32Value)
            case let dataValue as Data:
                try bindBlob(dataValue, to: statement, index: paramIndex)
            default:
                throw SQLiteDatabaseError.unexpected("Unsupported parameter type: \(type(of: parameter))")
            }
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            throw SQLiteDatabaseError.step(stepResult, currentErrorMessage())
        }

        return Int(sqlite3_changes(db))
    }
}
