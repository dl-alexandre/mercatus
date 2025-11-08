import Foundation

public struct SourceEvent {
    public let sourceEventID: String
    public let sourceSystem: String
    public let timestamp: Date
    public let rawData: [String: String]
}

public actor ExactlyOnceTracker {
    private var processedEvents: Set<String> = []
    private let maxSize: Int

    public init(maxSize: Int = 100_000) {
        self.maxSize = maxSize
    }

    public func isProcessed(_ eventID: String, sourceSystem: String) -> Bool {
        let key = "\(sourceSystem):\(eventID)"
        return processedEvents.contains(key)
    }

    public func markProcessed(_ eventID: String, sourceSystem: String) {
        let key = "\(sourceSystem):\(eventID)"
        processedEvents.insert(key)

        if processedEvents.count > maxSize {
            let toRemove = processedEvents.prefix(processedEvents.count - maxSize)
            for key in toRemove {
                processedEvents.remove(key)
            }
        }
    }

    public func verifyUniqueness(_ eventID: String, sourceSystem: String) throws {
        if isProcessed(eventID, sourceSystem: sourceSystem) {
            throw SmartVestorError.persistenceError("Duplicate event detected: \(sourceSystem):\(eventID)")
        }
        markProcessed(eventID, sourceSystem: sourceSystem)
    }
}

extension InvestmentTransaction {
    public var sourceEventID: String? {
        return metadata["source_event_id"]
    }

    public var sourceSystem: String? {
        return metadata["source_system"]
    }
}

extension TigerBeetlePersistence {
    func saveTransactionWithExactlyOnce(
        _ transaction: InvestmentTransaction,
        tracker: ExactlyOnceTracker?
    ) async throws {
        if let tracker = tracker,
           let eventID = transaction.sourceEventID,
           let sourceSystem = transaction.sourceSystem {
            try await tracker.verifyUniqueness(eventID, sourceSystem: sourceSystem)
        }

        try saveTransaction(transaction)
    }
}
