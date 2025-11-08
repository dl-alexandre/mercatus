import Foundation

public struct TraceContext {
    public let traceID: String
    public let spanID: String
    public let parentSpanID: String?

    public init(
        traceID: String = UUID().uuidString,
        spanID: String = UUID().uuidString,
        parentSpanID: String? = nil
    ) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
    }

    public func createChild() -> TraceContext {
        return TraceContext(
            traceID: traceID,
            spanID: UUID().uuidString,
            parentSpanID: spanID
        )
    }
}

extension InvestmentTransaction {
    public func withTraceID(_ traceID: String) -> InvestmentTransaction {
        var newMetadata = metadata
        newMetadata["trace_id"] = traceID
        return InvestmentTransaction(
            id: id,
            type: type,
            exchange: exchange,
            asset: asset,
            quantity: quantity,
            price: price,
            fee: fee,
            timestamp: timestamp,
            metadata: newMetadata,
            idempotencyKey: idempotencyKey
        )
    }

    public var traceID: String? {
        return metadata["trace_id"]
    }
}

extension ExecutionEngine {
    func createTracedTransaction(
        type: TransactionType,
        exchange: String,
        asset: String,
        quantity: Double,
        price: Double,
        fee: Double,
        traceContext: TraceContext
    ) -> InvestmentTransaction {
        var transaction = InvestmentTransaction(
            type: type,
            exchange: exchange,
            asset: asset,
            quantity: quantity,
            price: price,
            fee: fee,
            metadata: [
                "trace_id": traceContext.traceID,
                "span_id": traceContext.spanID
            ]
        )
        return transaction
    }
}
