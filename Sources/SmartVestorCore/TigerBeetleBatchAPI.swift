import Foundation

public struct TransferResult {
    public let transferID: UUID
    public let success: Bool
    public let error: TigerBeetleError?
}

public struct BatchTransferRequest {
    public let transfers: [TigerBeetleTransfer]
    public let idempotencyKeys: [String]
}

public extension TigerBeetlePersistence {
    func batchSaveTransactions(_ transactions: [InvestmentTransaction]) throws -> [TransferResult] {
        var results: [TransferResult] = []

        for transaction in transactions {
            do {
                try saveTransaction(transaction)
                results.append(TransferResult(
                    transferID: transaction.id,
                    success: true,
                    error: nil
                ))
            } catch let error as TigerBeetleError {
                results.append(TransferResult(
                    transferID: transaction.id,
                    success: false,
                    error: error
                ))
            } catch {
                results.append(TransferResult(
                    transferID: transaction.id,
                    success: false,
                    error: .unknownError(error.localizedDescription)
                ))
            }
        }

        return results
    }

    func getBalances(accountIDs: [(exchange: String, asset: String)]) throws -> [Holding] {
        var holdings: [Holding] = []

        for accountID in accountIDs {
            if let holding = try getAccount(exchange: accountID.exchange, asset: accountID.asset) {
                holdings.append(holding)
            }
        }

        return holdings
    }

    func getTransactionHistory(
        exchange: String,
        asset: String,
        sinceID: UUID? = nil,
        sinceTimestamp: Date? = nil,
        limit: Int = 100
    ) throws -> [InvestmentTransaction] {
        let allTransactions = try getTransactions(
            exchange: exchange,
            asset: asset,
            type: nil,
            limit: nil
        )

        var filtered = allTransactions

        if let sinceID = sinceID {
            if let index = filtered.firstIndex(where: { $0.id == sinceID }) {
                filtered = Array(filtered.prefix(index))
            }
        }

        if let sinceTimestamp = sinceTimestamp {
            filtered = filtered.filter { $0.timestamp >= sinceTimestamp }
        }

        return Array(filtered.prefix(limit))
    }
}
