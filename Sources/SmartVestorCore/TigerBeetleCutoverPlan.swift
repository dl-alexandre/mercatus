import Foundation
import Utils

public enum CutoverPhase {
    case mirror
    case readFromTigerBeetle
    case disableSQLiteWrites
}

public class TigerBeetleCutoverManager {
    private let sqlitePersistence: SQLitePersistence
    private let hybridPersistence: HybridPersistence
    private var currentPhase: CutoverPhase = .mirror
    private let logger: StructuredLogger

    public init(
        sqlitePersistence: SQLitePersistence,
        hybridPersistence: HybridPersistence,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.hybridPersistence = hybridPersistence
        self.logger = logger
    }

    public func shouldMirrorWrites() -> Bool {
        return currentPhase == .mirror || currentPhase == .readFromTigerBeetle
    }

    public func shouldReadFromSQLite() -> Bool {
        return currentPhase == .mirror
    }

    public func advancePhase() {
        switch currentPhase {
        case .mirror:
            currentPhase = .readFromTigerBeetle
            logger.info(component: "TigerBeetleCutoverManager", event: "Advanced to read phase")
        case .readFromTigerBeetle:
            currentPhase = .disableSQLiteWrites
            logger.info(component: "TigerBeetleCutoverManager", event: "Advanced to disable SQLite writes")
        case .disableSQLiteWrites:
            break
        }
    }

    public func rollback() {
        currentPhase = .mirror
        logger.warn(component: "TigerBeetleCutoverManager", event: "Rolled back to mirror phase")
    }
}
