import Foundation
import SQLite3

public class SQLiteBackupManager {
    private let dbPath: String

    public init(dbPath: String) {
        self.dbPath = dbPath
    }

    public func createBackup(to backupPath: String) throws {
        var sourceDB: OpaquePointer?
        var destDB: OpaquePointer?
        var backup: OpaquePointer?

        guard sqlite3_open(dbPath, &sourceDB) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to open source database: \(dbPath)")
        }

        defer {
            sqlite3_close(sourceDB)
        }

        guard sqlite3_open(backupPath, &destDB) == SQLITE_OK else {
            throw SmartVestorError.persistenceError("Failed to open destination database: \(backupPath)")
        }

        defer {
            sqlite3_close(destDB)
        }

        backup = sqlite3_backup_init(destDB, "main", sourceDB, "main")
        guard backup != nil else {
            throw SmartVestorError.persistenceError("Failed to initialize backup")
        }

        defer {
            sqlite3_backup_finish(backup)
        }

        let result = sqlite3_backup_step(backup, -1)
        guard result == SQLITE_DONE else {
            throw SmartVestorError.persistenceError("Backup failed with code: \(result)")
        }
    }
}
