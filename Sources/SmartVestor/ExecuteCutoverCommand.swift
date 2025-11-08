import Foundation
import ArgumentParser
import SmartVestor
import Utils

public struct ExecuteCutoverCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "execute-cutover",
        abstract: "Execute fast cutover to TigerBeetle"
    )

    public init() {}

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    public func run() async throws {
        print("⚠️  FAST CUTOVER MODE")
        print("This will:")
        print("  1. Freeze writes for 2-3 minutes")
        print("  2. Create SQLite backup and export ledger")
        print("  3. Verify parity (zero drift expected)")
        print("  4. Flip to TigerBeetle as source of truth")
        print("  5. Unfreeze writes")
        print("  6. Run immediate smoke tests")
        print("")

        if !force {
            print("Type 'YES' to proceed:")
            guard let confirmation = readLine(), confirmation == "YES" else {
                print("Cutover cancelled.")
                return
            }
        }

        let configManager = try SmartVestorConfigurationManager()
        let config = configManager.currentConfig

        guard let tbConfig = config.tigerbeetle, tbConfig.enabled else {
            throw SmartVestorError.configurationError("TigerBeetle not enabled in config")
        }

        let sqlitePersistence = SQLitePersistence(dbPath: "smartvestor.db")
        let client = InMemoryTigerBeetleClient()
        let tbPersistence = TigerBeetlePersistence(client: client)
        let featureFlags = FeatureFlagManager()

        let hybridPersistence = HybridPersistence(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tbPersistence,
            useTigerBeetleForTransactions: tbConfig.useTigerBeetleForTransactions,
            useTigerBeetleForBalances: tbConfig.useTigerBeetleForBalances,
            featureFlags: featureFlags
        )

        let smokeTests = TigerBeetleSmokeTests(
            persistence1: hybridPersistence,
            persistence2: hybridPersistence
        )

        let sloMonitor = SLOMonitor()
        let extendedMetrics = TigerBeetleExtendedMetrics()

        let cutoverManager = FastCutoverManager(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tbPersistence,
            hybridPersistence: hybridPersistence,
            featureFlags: featureFlags,
            smokeTests: smokeTests,
            sloMonitor: sloMonitor,
            extendedMetrics: extendedMetrics
        )

        print("🚀 Starting fast cutover...")
        let result = try await cutoverManager.executeFastCutover()

        switch result {
        case .success(let smokeResults):
            print("✅ Cutover completed successfully!")
            if !smokeResults.violations.isEmpty {
                print("⚠️  Warnings:")
                for violation in smokeResults.violations {
                    print("   - \(violation)")
                }
            }
        case .partialSuccess(let smokeResults):
            print("⚠️  Cutover completed with warnings:")
            for violation in smokeResults.violations {
                print("   - \(violation)")
            }
        case .failure(let error):
            print("❌ Cutover failed: \(error.localizedDescription)")
            throw error
        }
    }
}

public struct RollbackCutoverCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rollback-cutover",
        abstract: "Rollback cutover to SQLite"
    )

    public init() {}

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    public func run() async throws {
        print("⚠️  ROLLBACK MODE")
        print("This will:")
        print("  1. Disable TigerBeetle")
        print("  2. Rebuild SQLite from TigerBeetle")
        print("  3. Route all reads/writes back to SQLite")
        print("")

        if !force {
            print("Type 'YES' to proceed:")
            guard let confirmation = readLine(), confirmation == "YES" else {
                print("Rollback cancelled.")
                return
            }
        }

        let sqlitePersistence = SQLitePersistence(dbPath: "smartvestor.db")
        let client = InMemoryTigerBeetleClient()
        let tbPersistence = TigerBeetlePersistence(client: client)
        let featureFlags = FeatureFlagManager()

        let hybridPersistence = HybridPersistence(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tbPersistence,
            featureFlags: featureFlags
        )

        let cutoverManager = FastCutoverManager(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tbPersistence,
            hybridPersistence: hybridPersistence,
            featureFlags: featureFlags,
            smokeTests: TigerBeetleSmokeTests(persistence1: hybridPersistence, persistence2: hybridPersistence),
            sloMonitor: SLOMonitor(),
            extendedMetrics: TigerBeetleExtendedMetrics()
        )

        print("🔄 Starting rollback...")
        try await cutoverManager.executeRollback()
        print("✅ Rollback completed. System now using SQLite.")
    }
}
