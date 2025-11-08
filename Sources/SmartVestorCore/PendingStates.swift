import Foundation

public struct PendingAccountMapping {
    public static func pendingAccountID(exchange: String, asset: String) -> UUID {
        return AccountMapping.accountID(exchange: exchange, asset: "\(asset)_PENDING")
    }

    public static func createPendingTransfer(
        from mainAccountID: UUID,
        to pendingAccountID: UUID,
        amount: UInt128,
        transactionID: UUID
    ) -> TigerBeetleTransfer {
        return TigerBeetleTransfer(
            id: UUID(),
            debitAccountID: mainAccountID,
            creditAccountID: pendingAccountID,
            amount: amount,
            flags: .pending,
            userData: UInt128(UInt64(bitPattern: Int64(transactionID.hashValue)))
        )
    }

    public static func releasePendingTransfer(
        from pendingAccountID: UUID,
        to mainAccountID: UUID,
        amount: UInt128,
        originalTransferID: UUID
    ) -> TigerBeetleTransfer {
        return TigerBeetleTransfer(
            id: UUID(),
            debitAccountID: pendingAccountID,
            creditAccountID: mainAccountID,
            amount: amount,
            pendingID: originalTransferID,
            flags: .postPendingTransfer,
            userData: UInt128(UInt64(bitPattern: Int64(originalTransferID.hashValue)))
        )
    }
}

extension TigerBeetlePersistence {
    func getAvailableBalance(exchange: String, asset: String) throws -> Double {
        let account = try getAccount(exchange: exchange, asset: asset)
        return account?.available ?? 0.0
    }

    func getPendingBalance(exchange: String, asset: String) throws -> Double {
        let pendingAccount = try getAccount(exchange: exchange, asset: "\(asset)_PENDING")
        return pendingAccount?.pending ?? 0.0
    }
}
