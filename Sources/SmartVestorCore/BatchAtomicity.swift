import Foundation

public struct TransactionGroup {
    public let groupID: UUID
    public let transfers: [TigerBeetleTransfer]
    public let metadata: [String: String]

    public init(
        groupID: UUID = UUID(),
        transfers: [TigerBeetleTransfer],
        metadata: [String: String] = [:]
    ) {
        self.groupID = groupID
        self.transfers = transfers
        self.metadata = metadata
    }
}

extension TigerBeetlePersistence {
    public func saveTransactionGroup(_ group: TransactionGroup) throws {
        let errors: [TigerBeetleError]
        let clientInstance = (self as TigerBeetlePersistence).client
        if let actorClient = clientInstance as? InMemoryTigerBeetleClient {
            errors = try callActor {
                try await actorClient.createTransfers(group.transfers)
            }
        } else {
            errors = try self.client.createTransfers(group.transfers)
        }

        if !errors.isEmpty {
            throw SmartVestorError.persistenceError("TigerBeetle error: \(errors.first!)")
        }
    }

    public func createMultiStepTrade(
        mainTransfer: TigerBeetleTransfer,
        feeTransfer: TigerBeetleTransfer?,
        traceID: String
    ) -> TransactionGroup {
        var transfers = [mainTransfer]
        if let fee = feeTransfer {
            transfers.append(fee)
        }

        return TransactionGroup(
            groupID: UUID(),
            transfers: transfers,
            metadata: ["trace_id": traceID]
        )
    }
}
