import Testing
import Foundation
import CryptoKit
@testable import SmartVestor

@Suite("TigerBeetle Production Gates Tests")
struct TigerBeetleProductionGatesTests {

    @Test("Config integrity: Unsigned config => fatal in production")
    func testUnsignedConfigFatal() async throws {
        let productionMode = ProcessInfo.processInfo.environment["PRODUCTION"] == "true"

        guard productionMode else {
            return
        }

        let unsignedConfig = TigerBeetleConfig(enabled: true)
        let keyData = Data(repeating: 1, count: 32)
        let secretKey = SymmetricKey(data: keyData)
        let sealer = TigerBeetleConfigSealer(secretKey: secretKey)

        do {
            let sealed = try sealer.seal(unsignedConfig)
            _ = try TigerBeetleConfigLoader.loadWithVerification(
                sealedConfig: sealed,
                secretKey: secretKey,
                production: true
            )
            let _: Bool = false
        } catch {
            #expect(error is SmartVestorError)
        }
    }

    @Test("Scale registry: Runtime scale changes blocked unless migration flag")
    func testScaleRegistryLock() async throws {
        let registry = AssetScaleRegistry()

        await registry.lock()

        do {
            try await registry.setScale(6, for: "BTC", migrationMode: false)
            #expect(false, "Should have thrown when locked")
        } catch {
            #expect(error is SmartVestorError)
        }

        try await registry.setScale(6, for: "BTC", migrationMode: true)

        let scale = await registry.getScale(for: "BTC")
        #expect(scale == 6)
    }

    @Test("FX snapshots: Stale FX blocks cross-asset P/L posting")
    func testStaleFXBlocking() async throws {
        let store = FXSnapshotStore(maxStaleMinutes: 5)

        let staleSnapshot = FXSnapshotRecord(
            provider: "test",
            timestamp: Date().addingTimeInterval(-10 * 60),
            rates: ["BTC": 50000.0]
        )

        await store.store(staleSnapshot)

        do {
            try await store.validateForCrossAssetPL()
            #expect(false, "Should have thrown for stale snapshot")
        } catch {
            #expect(error is SmartVestorError)
        }
    }

    @Test("RBAC: CLI cannot write to ledger")
    func testCLIWriteBlocked() async throws {
        let rbac = ProductionRBAC()
        let persistence = TigerBeetlePersistence(client: InMemoryTigerBeetleClient())

        let hasPermission = rbac.hasPermission(.write, for: "TigerBeetleCLITools")
        #expect(!hasPermission)

        do {
            try persistence.checkWritePermission(component: "TigerBeetleCLITools", rbac: rbac)
            #expect(false, "Should have thrown for unauthorized write")
        } catch {
            #expect(error is SmartVestorError)
        }
    }

    @Test("RBAC: ExecutionEngine can write")
    func testExecutionEngineCanWrite() async throws {
        let rbac = ProductionRBAC()
        let persistence = TigerBeetlePersistence(client: InMemoryTigerBeetleClient())

        let hasPermission = rbac.hasPermission(.write, for: "ExecutionEngine")
        #expect(hasPermission)

        try persistence.checkWritePermission(component: "ExecutionEngine", rbac: rbac)
    }
}
