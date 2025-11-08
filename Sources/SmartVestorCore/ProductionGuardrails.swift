import Foundation
import Utils

public class ProductionGuardrails {
    private let scaleRegistry: AssetScaleRegistry
    private let fxSnapshotStore: FXSnapshotStore?
    private let logger: StructuredLogger

    public init(
        scaleRegistry: AssetScaleRegistry,
        fxSnapshotStore: FXSnapshotStore? = nil,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.scaleRegistry = scaleRegistry
        self.fxSnapshotStore = fxSnapshotStore
        self.logger = logger
    }

    public func freezeScaleRegistry() async {
        await scaleRegistry.lock()
        logger.info(component: "ProductionGuardrails", event: "Scale registry frozen")
    }

    public func validateScaleChange(asset: String, scale: Int, migrationMode: Bool) async throws {
        guard migrationMode else {
            throw SmartVestorError.configurationError("Scale registry is locked. Migration mode required.")
        }
        try await scaleRegistry.setScale(scale, for: asset, migrationMode: true)
    }

    public func validateFXFreshness() async throws {
        guard let store = fxSnapshotStore else { return }
        try await store.validateForCrossAssetPL()
    }

    public func validateBatchAtomicity(group: TransactionGroup) throws -> Bool {
        guard !group.transfers.isEmpty else {
            logger.error(component: "ProductionGuardrails", event: "Batch atomicity violation: empty group")
            return false
        }

        let groupIDHash = UInt128(UInt64(bitPattern: Int64(group.groupID.hashValue)))
        let allHaveSameGroupID = group.transfers.allSatisfy { transfer in
            transfer.userData == groupIDHash
        }

        if !allHaveSameGroupID {
            logger.error(component: "ProductionGuardrails", event: "Batch atomicity violation: inconsistent group IDs")
            return false
        }

        return true
    }

    public func validatePendingModel(account: TigerBeetleAccount) throws {
        let available = account.availableBalance

        if account.creditsAccepted < account.debitsAccepted || account.creditsAccepted < (account.debitsAccepted + account.debitsReserved) {
            logger.error(
                component: "ProductionGuardrails",
                event: "Negative available balance detected",
                data: [
                    "account_id": account.id.uuidString,
                    "credits_accepted": String(account.creditsAccepted.asDouble),
                    "debits_accepted": String(account.debitsAccepted.asDouble),
                    "debits_reserved": String(account.debitsReserved.asDouble),
                    "available": String(available.asDouble)
                ]
            )
            throw SmartVestorError.persistenceError("Negative available balance detected for account \(account.id.uuidString)")
        }
    }
}
