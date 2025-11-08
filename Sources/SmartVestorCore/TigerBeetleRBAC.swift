import Foundation

public enum LedgerPermission {
    case read
    case write
    case admin
}

public protocol LedgerAccessControl {
    func hasPermission(_ permission: LedgerPermission, for component: String) -> Bool
}

public class ProductionRBAC: LedgerAccessControl {
    private let allowedWriters: Set<String> = ["ExecutionEngine"]
    private let allowedReaders: Set<String> = ["TigerBeetleCLITools", "Dashboard", "Reconciliation"]

    public init() {}

    public func hasPermission(_ permission: LedgerPermission, for component: String) -> Bool {
        switch permission {
        case .write:
            return allowedWriters.contains(component)
        case .read:
            return allowedReaders.contains(component) || allowedWriters.contains(component)
        case .admin:
            return false
        }
    }
}

extension TigerBeetlePersistence {
    func checkWritePermission(component: String, rbac: LedgerAccessControl?) throws {
        guard let rbac = rbac else { return }

        guard rbac.hasPermission(.write, for: component) else {
            throw SmartVestorError.persistenceError("Component '\(component)' does not have write permission")
        }
    }
}

extension ExecutionEngine {
    private func checkLedgerWritePermission(rbac: LedgerAccessControl?) throws {
        guard let rbac = rbac else { return }

        guard rbac.hasPermission(.write, for: "ExecutionEngine") else {
            throw SmartVestorError.executionError("ExecutionEngine does not have ledger write permission")
        }
    }
}
