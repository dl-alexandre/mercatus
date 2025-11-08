import Foundation
import Utils
import Core

public struct ConfigValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String], warnings: [String]) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

public struct ConfigValidator {
    private static func validateDatabasePath(dbPath: String) -> Bool {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: dbPath).deletingLastPathComponent()

        // Check if directory exists and is writable
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        // Check if directory is writable
        return fileManager.isWritableFile(atPath: directory.path)
    }

    public static func validate(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        connectors: [String: ExchangeConnectorProtocol],
        processLockManager: ProcessLockManager
    ) async throws -> ConfigValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Validate database initialization and migrations
        do {
            try persistence.initialize()
        } catch {
            errors.append("Database initialization failed: \(error.localizedDescription)")
        }

        // Validate deposit amount > 0
        if config.depositAmount <= 0 {
            errors.append("Deposit amount must be greater than 0 (current: \(config.depositAmount))")
        }

        // Validate allocation percentages sum to 1.0 (with tolerance)
        let totalAllocation = config.baseAllocation.btc + config.baseAllocation.eth + config.baseAllocation.altcoins
        if abs(totalAllocation - 1.0) > 0.01 {
            errors.append("Base allocation percentages must sum to 1.0 (current: \(String(format: "%.2f", totalAllocation)))")
        }

        // Validate fee cap is reasonable
        if config.feeCap <= 0 || config.feeCap > 0.1 {
            warnings.append("Fee cap is \(String(format: "%.3f%%", config.feeCap * 100)) - verify this is correct")
        }

        // Check if PID lock indicates already running
        if processLockManager.isLocked() {
            let currentPid = ProcessInfo.processInfo.processIdentifier
            if let lockPid = processLockManager.getLockPid(), lockPid != currentPid {
                errors.append("Automation already running (PID: \(lockPid)) - use 'stop' command first or remove .automation.pid file")
            } else if processLockManager.getLockPid() == nil {
                errors.append("Automation lock file exists - another instance may be running")
            }
        }

        // Validate exchange connectors for enabled exchanges
        for exchangeConfig in config.exchanges where exchangeConfig.enabled {
            if connectors[exchangeConfig.name] == nil {
                warnings.append("Exchange '\(exchangeConfig.name)' is enabled but connector not available")
            }
        }

        // Validate RSI threshold is in reasonable range
        if config.rsiThreshold < 30 || config.rsiThreshold > 90 {
            warnings.append("RSI threshold \(config.rsiThreshold) is outside typical range (30-90)")
        }

        // Validate price threshold is reasonable
        if config.priceThreshold < 1.0 || config.priceThreshold > 2.0 {
            warnings.append("Price threshold \(config.priceThreshold) is outside typical range (1.0-2.0)")
        }

        return ConfigValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}
