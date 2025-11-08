import Foundation

public struct TigerBeetleAccount: Sendable {
    public let id: UUID
    public let code: UInt16
    public let debitsReserved: UInt128
    public let debitsAccepted: UInt128
    public let creditsReserved: UInt128
    public let creditsAccepted: UInt128
    public let flags: AccountFlags

    public init(
        id: UUID,
        code: UInt16 = 1,
        debitsReserved: UInt128 = UInt128(0, 0),
        debitsAccepted: UInt128 = UInt128(0, 0),
        creditsReserved: UInt128 = UInt128(0, 0),
        creditsAccepted: UInt128 = UInt128(0, 0),
        flags: AccountFlags = []
    ) {
        self.id = id
        self.code = code
        self.debitsReserved = debitsReserved
        self.debitsAccepted = debitsAccepted
        self.creditsReserved = creditsReserved
        self.creditsAccepted = creditsAccepted
        self.flags = flags
    }

    public var balance: Int128 {
        let creditsHigh = Int64(bitPattern: creditsAccepted.high)
        let debitsHigh = Int64(bitPattern: debitsAccepted.high)
        let credits = Int128(creditsHigh, creditsAccepted.low)
        let debits = Int128(debitsHigh, debitsAccepted.low)
        return credits - debits
    }

    public var availableBalance: UInt128 {
        let reserved = debitsReserved
        let credits = creditsAccepted
        let debits = debitsAccepted

        if credits < (debits + reserved) {
            return UInt128(0, 0)
        }
        return credits - debits - reserved
    }
}

public struct UInt128: Sendable {
    public let high: UInt64
    public let low: UInt64

    public init(_ high: UInt64 = 0, _ low: UInt64 = 0) {
        self.high = high
        self.low = low
    }

    public init(_ value: UInt64) {
        self.high = 0
        self.low = value
    }

    public init(_ value: Double) {
        let uintValue = UInt64(value * 1_000_000)
        self.high = 0
        self.low = uintValue
    }

    public var asDouble: Double {
        return Double(low) / 1_000_000.0
    }

    static func < (lhs: UInt128, rhs: UInt128) -> Bool {
        if lhs.high != rhs.high {
            return lhs.high < rhs.high
        }
        return lhs.low < rhs.low
    }

    static func > (lhs: UInt128, rhs: UInt128) -> Bool {
        return rhs < lhs
    }

    static func >= (lhs: UInt128, rhs: UInt128) -> Bool {
        return !(lhs < rhs)
    }

    static func - (lhs: UInt128, rhs: UInt128) -> UInt128 {
        if lhs.low < rhs.low {
            return UInt128(lhs.high - rhs.high - 1, lhs.low - rhs.low)
        }
        return UInt128(lhs.high - rhs.high, lhs.low - rhs.low)
    }

    static func + (lhs: UInt128, rhs: UInt128) -> UInt128 {
        let low = lhs.low + rhs.low
        let high = lhs.high + rhs.high
        if low < lhs.low {
            return UInt128(high + 1, low)
        }
        return UInt128(high, low)
    }
}

public struct Int128 {
    public let high: Int64
    public let low: UInt64

    public init(_ high: Int64 = 0, _ low: UInt64 = 0) {
        self.high = high
        self.low = low
    }

    public init(_ value: Int64) {
        self.high = value < 0 ? -1 : 0
        self.low = UInt64(bitPattern: value)
    }

    static func - (lhs: Int128, rhs: Int128) -> Int128 {
        if lhs.low >= rhs.low {
            return Int128(lhs.high - rhs.high, lhs.low - rhs.low)
        } else {
            return Int128(lhs.high - rhs.high - 1, UInt64.max - (rhs.low - lhs.low) + 1)
        }
    }

    public var asDouble: Double {
        let unsigned = UInt128(UInt64(bitPattern: high), low)
        return unsigned.asDouble * (high < 0 ? -1.0 : 1.0)
    }
}

extension UInt128: Equatable {
    public static func == (lhs: UInt128, rhs: UInt128) -> Bool {
        return lhs.high == rhs.high && lhs.low == rhs.low
    }
}

public struct AccountFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let linked = AccountFlags(rawValue: 1 << 0)
    public static let debitsMustNotExceedCredits = AccountFlags(rawValue: 1 << 1)
    public static let creditsMustNotExceedDebits = AccountFlags(rawValue: 1 << 2)
}

public struct TigerBeetleTransfer: Sendable {
    public let id: UUID
    public let debitAccountID: UUID
    public let creditAccountID: UUID
    public let amount: UInt128
    public let pendingID: UUID
    public let timeout: UInt32
    public let ledger: UInt32
    public let code: UInt16
    public let flags: TransferFlags
    public let timestamp: UInt64
    public let userData: UInt128
    public let memo: [UInt8]

    public init(
        id: UUID = UUID(),
        debitAccountID: UUID,
        creditAccountID: UUID,
        amount: UInt128,
        pendingID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        timeout: UInt32 = 0,
        ledger: UInt32 = 1,
        code: UInt16 = 1,
        flags: TransferFlags = [],
        timestamp: UInt64 = 0,
        userData: UInt128 = UInt128(0, 0),
        memo: [UInt8] = []
    ) {
        self.id = id
        self.debitAccountID = debitAccountID
        self.creditAccountID = creditAccountID
        self.amount = amount
        self.pendingID = pendingID
        self.timeout = timeout
        self.ledger = ledger
        self.code = code
        self.flags = flags
        self.timestamp = timestamp
        self.userData = userData
        self.memo = memo
    }
}

public struct TransferFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let linked = TransferFlags(rawValue: 1 << 0)
    public static let pending = TransferFlags(rawValue: 1 << 1)
    public static let postPendingTransfer = TransferFlags(rawValue: 1 << 2)
    public static let voidPendingTransfer = TransferFlags(rawValue: 1 << 3)
}

public protocol TigerBeetleClientProtocol {
    func createAccounts(_ accounts: [TigerBeetleAccount]) throws -> [TigerBeetleError]
    func lookupAccounts(_ accountIDs: [UUID]) throws -> [TigerBeetleAccount]
    func createTransfers(_ transfers: [TigerBeetleTransfer]) throws -> [TigerBeetleError]
    func lookupTransfers(_ transferIDs: [UUID]) throws -> [TigerBeetleTransfer]
}

public enum TigerBeetleError: Error, Equatable {
    case exceedsDebits
    case exceedsCredits
    case exceedsDebitsPending
    case exceedsCreditsPending
    case insufficientFunds
    case duplicateTransfer
    case accountNotFound
    case transferNotFound
    case accountExists
    case invalidAmount
    case invalidAccount
    case invalidTransfer
    case connectionError(String)
    case unknownError(String)

    public static func fromErrorCode(_ code: UInt32) -> TigerBeetleError {
        switch code {
        case 1: return .exceedsDebits
        case 2: return .exceedsCredits
        case 3: return .exceedsDebitsPending
        case 4: return .exceedsCreditsPending
        case 5: return .insufficientFunds
        case 6: return .duplicateTransfer
        case 7: return .accountNotFound
        case 8: return .transferNotFound
        case 9: return .accountExists
        case 10: return .invalidAmount
        case 11: return .invalidAccount
        case 12: return .invalidTransfer
        default: return .unknownError("Error code: \(code)")
        }
    }
}

@preconcurrency @MainActor
public class InMemoryTigerBeetleClient: TigerBeetleClientProtocol, @unchecked Sendable {
    private var accounts: [UUID: TigerBeetleAccount] = [:]
    private var transfers: [UUID: TigerBeetleTransfer] = [:]

    nonisolated public init() {}

    nonisolated public func createAccounts(_ accounts: [TigerBeetleAccount]) throws -> [TigerBeetleError] {
        return try Task<[TigerBeetleError], Error>.runBlocking(operation: {
            await MainActor.run {
                var errors: [TigerBeetleError] = []
                for account in accounts {
                    if self.accounts[account.id] != nil {
                        errors.append(.accountExists)
                        continue
                    }
                    self.accounts[account.id] = account
                }
                return errors
            }
        })
    }

    nonisolated public func lookupAccounts(_ accountIDs: [UUID]) throws -> [TigerBeetleAccount] {
        return try Task<[TigerBeetleAccount], Error>.runBlocking(operation: {
            await MainActor.run {
                return accountIDs.compactMap { self.accounts[$0] }
            }
        })
    }

    nonisolated public func createTransfers(_ transfers: [TigerBeetleTransfer]) throws -> [TigerBeetleError] {
        return try Task<[TigerBeetleError], Error>.runBlocking(operation: {
            await MainActor.run {
                var errors: [TigerBeetleError] = []

                for transfer in transfers {
                    if self.transfers[transfer.id] != nil {
                        errors.append(.duplicateTransfer)
                        continue
                    }

                    guard let debitAccount = self.accounts[transfer.debitAccountID] else {
                        errors.append(.accountNotFound)
                        continue
                    }

                    guard let creditAccount = self.accounts[transfer.creditAccountID] else {
                        errors.append(.accountNotFound)
                        continue
                    }

                    let debitAvailable = debitAccount.availableBalance
                    if transfer.amount > debitAvailable {
                        errors.append(.insufficientFunds)
                        continue
                    }

                    if transfer.flags.contains(.pending) {
                        let debitsReserved = debitAccount.debitsReserved + transfer.amount
                        let creditsReserved = creditAccount.creditsReserved + transfer.amount

                        if debitsReserved < transfer.amount {
                            errors.append(.exceedsDebitsPending)
                            continue
                        }

                        if creditsReserved < transfer.amount {
                            errors.append(.exceedsCreditsPending)
                            continue
                        }

                        let updatedDebit = TigerBeetleAccount(
                            id: debitAccount.id,
                            code: debitAccount.code,
                            debitsReserved: debitsReserved,
                            debitsAccepted: debitAccount.debitsAccepted,
                            creditsReserved: debitAccount.creditsReserved,
                            creditsAccepted: debitAccount.creditsAccepted,
                            flags: debitAccount.flags
                        )

                        let updatedCredit = TigerBeetleAccount(
                            id: creditAccount.id,
                            code: creditAccount.code,
                            debitsReserved: creditAccount.debitsReserved,
                            debitsAccepted: creditAccount.debitsAccepted,
                            creditsReserved: creditsReserved,
                            creditsAccepted: creditAccount.creditsAccepted,
                            flags: creditAccount.flags
                        )

                        self.accounts[transfer.debitAccountID] = updatedDebit
                        self.accounts[transfer.creditAccountID] = updatedCredit
                    } else {
                        let newDebitsAccepted = debitAccount.debitsAccepted + transfer.amount
                        let newCreditsAccepted = creditAccount.creditsAccepted + transfer.amount

                        let updatedDebit = TigerBeetleAccount(
                            id: debitAccount.id,
                            code: debitAccount.code,
                            debitsReserved: debitAccount.debitsReserved,
                            debitsAccepted: newDebitsAccepted,
                            creditsReserved: debitAccount.creditsReserved,
                            creditsAccepted: debitAccount.creditsAccepted,
                            flags: debitAccount.flags
                        )

                        let updatedCredit = TigerBeetleAccount(
                            id: creditAccount.id,
                            code: creditAccount.code,
                            debitsReserved: creditAccount.debitsReserved,
                            debitsAccepted: creditAccount.debitsAccepted,
                            creditsReserved: creditAccount.creditsReserved,
                            creditsAccepted: newCreditsAccepted,
                            flags: creditAccount.flags
                        )

                        self.accounts[transfer.debitAccountID] = updatedDebit
                        self.accounts[transfer.creditAccountID] = updatedCredit
                    }

                    self.transfers[transfer.id] = transfer
                }

                return errors
            }
        })
    }

    nonisolated public func lookupTransfers(_ transferIDs: [UUID]) throws -> [TigerBeetleTransfer] {
        return try Task<[TigerBeetleTransfer], Error>.runBlocking(operation: {
            await MainActor.run {
                return transferIDs.compactMap { self.transfers[$0] }
            }
        })
    }
}
