import Foundation
import Utils

public enum ArbitrageError: Error, Sendable, Equatable {
    case connection(ConnectionError)
    case data(DataError)
    case logic(LogicError)

    public enum ConnectionError: Sendable, Equatable {
        case failedToConnect(exchange: String, reason: String)
        case connectionLost(exchange: String, reason: String?)
        case subscriptionFailed(exchange: String, pairs: [String], reason: String)
        case authenticationFailed(exchange: String, reason: String)
        case circuitBreakerOpen(exchange: String, failureCount: Int)
        case timeout(exchange: String, operation: String)
        case invalidURL(exchange: String, url: String)
        case websocketError(exchange: String, code: Int, reason: String)
    }

    public enum DataError: Sendable, Equatable {
        case invalidFormat(exchange: String, reason: String)
        case missingField(exchange: String, field: String)
        case invalidPrice(exchange: String, symbol: String, reason: String)
        case staleData(exchange: String, symbol: String, age: TimeInterval)
        case normalizationFailed(exchange: String, symbol: String, reason: String)
        case invalidJSON(exchange: String, reason: String)
        case unsupportedMessageType(exchange: String, type: String)
        case decodingFailed(exchange: String, type: String, reason: String)
    }

    public enum LogicError: Sendable, Equatable {
        case invalidConfiguration(field: String, reason: String)
        case spreadCalculationFailed(symbol: String, reason: String)
        case insufficientBalance(required: Decimal, available: Decimal)
        case invalidState(component: String, expected: String, actual: String)
        case operationNotAllowed(component: String, operation: String, reason: String)
        case internalError(component: String, reason: String)
    }

    public var localizedDescription: String {
        switch self {
        case .connection(let error):
            return "Connection error: \(error.description)"
        case .data(let error):
            return "Data error: \(error.description)"
        case .logic(let error):
            return "Logic error: \(error.description)"
        }
    }

    public var category: String {
        switch self {
        case .connection: return "connection"
        case .data: return "data"
        case .logic: return "logic"
        }
    }

    public var logData: [String: String] {
        var data = ["category": category]

        switch self {
        case .connection(let error):
            data.merge(error.logData, uniquingKeysWith: { $1 })
        case .data(let error):
            data.merge(error.logData, uniquingKeysWith: { $1 })
        case .logic(let error):
            data.merge(error.logData, uniquingKeysWith: { $1 })
        }

        return data
    }
}

extension ArbitrageError.ConnectionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .failedToConnect(let exchange, let reason):
            return "Failed to connect to \(exchange): \(reason)"
        case .connectionLost(let exchange, let reason):
            return "Connection lost to \(exchange): \(reason ?? "unknown")"
        case .subscriptionFailed(let exchange, let pairs, let reason):
            return "Failed to subscribe to \(pairs.joined(separator: ", ")) on \(exchange): \(reason)"
        case .authenticationFailed(let exchange, let reason):
            return "Authentication failed for \(exchange): \(reason)"
        case .circuitBreakerOpen(let exchange, let failureCount):
            return "Circuit breaker open for \(exchange) after \(failureCount) failures"
        case .timeout(let exchange, let operation):
            return "Operation \(operation) timed out for \(exchange)"
        case .invalidURL(let exchange, let url):
            return "Invalid URL for \(exchange): \(url)"
        case .websocketError(let exchange, let code, let reason):
            return "WebSocket error for \(exchange) (code \(code)): \(reason)"
        }
    }

    public var logData: [String: String] {
        var data: [String: String] = ["error_type": "connection"]

        switch self {
        case .failedToConnect(let exchange, let reason):
            data["exchange"] = exchange
            data["reason"] = reason
            data["error"] = "failed_to_connect"
        case .connectionLost(let exchange, let reason):
            data["exchange"] = exchange
            data["error"] = "connection_lost"
            if let reason { data["reason"] = reason }
        case .subscriptionFailed(let exchange, let pairs, let reason):
            data["exchange"] = exchange
            data["pairs"] = pairs.joined(separator: ",")
            data["reason"] = reason
            data["error"] = "subscription_failed"
        case .authenticationFailed(let exchange, let reason):
            data["exchange"] = exchange
            data["reason"] = reason
            data["error"] = "authentication_failed"
        case .circuitBreakerOpen(let exchange, let failureCount):
            data["exchange"] = exchange
            data["failure_count"] = String(failureCount)
            data["error"] = "circuit_breaker_open"
        case .timeout(let exchange, let operation):
            data["exchange"] = exchange
            data["operation"] = operation
            data["error"] = "timeout"
        case .invalidURL(let exchange, let url):
            data["exchange"] = exchange
            data["url"] = url
            data["error"] = "invalid_url"
        case .websocketError(let exchange, let code, let reason):
            data["exchange"] = exchange
            data["code"] = String(code)
            data["reason"] = reason
            data["error"] = "websocket_error"
        }

        return data
    }
}

extension ArbitrageError.DataError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidFormat(let exchange, let reason):
            return "Invalid data format from \(exchange): \(reason)"
        case .missingField(let exchange, let field):
            return "Missing required field '\(field)' from \(exchange)"
        case .invalidPrice(let exchange, let symbol, let reason):
            return "Invalid price for \(symbol) on \(exchange): \(reason)"
        case .staleData(let exchange, let symbol, let age):
            return "Stale data for \(symbol) on \(exchange) (age: \(String(format: "%.2f", age))s)"
        case .normalizationFailed(let exchange, let symbol, let reason):
            return "Failed to normalize \(symbol) data from \(exchange): \(reason)"
        case .invalidJSON(let exchange, let reason):
            return "Invalid JSON from \(exchange): \(reason)"
        case .unsupportedMessageType(let exchange, let type):
            return "Unsupported message type '\(type)' from \(exchange)"
        case .decodingFailed(let exchange, let type, let reason):
            return "Failed to decode \(type) from \(exchange): \(reason)"
        }
    }

    public var logData: [String: String] {
        var data: [String: String] = ["error_type": "data"]

        switch self {
        case .invalidFormat(let exchange, let reason):
            data["exchange"] = exchange
            data["reason"] = reason
            data["error"] = "invalid_format"
        case .missingField(let exchange, let field):
            data["exchange"] = exchange
            data["field"] = field
            data["error"] = "missing_field"
        case .invalidPrice(let exchange, let symbol, let reason):
            data["exchange"] = exchange
            data["symbol"] = symbol
            data["reason"] = reason
            data["error"] = "invalid_price"
        case .staleData(let exchange, let symbol, let age):
            data["exchange"] = exchange
            data["symbol"] = symbol
            data["age_seconds"] = String(format: "%.2f", age)
            data["error"] = "stale_data"
        case .normalizationFailed(let exchange, let symbol, let reason):
            data["exchange"] = exchange
            data["symbol"] = symbol
            data["reason"] = reason
            data["error"] = "normalization_failed"
        case .invalidJSON(let exchange, let reason):
            data["exchange"] = exchange
            data["reason"] = reason
            data["error"] = "invalid_json"
        case .unsupportedMessageType(let exchange, let type):
            data["exchange"] = exchange
            data["message_type"] = type
            data["error"] = "unsupported_message_type"
        case .decodingFailed(let exchange, let type, let reason):
            data["exchange"] = exchange
            data["type"] = type
            data["reason"] = reason
            data["error"] = "decoding_failed"
        }

        return data
    }
}

extension ArbitrageError.LogicError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidConfiguration(let field, let reason):
            return "Invalid configuration for '\(field)': \(reason)"
        case .spreadCalculationFailed(let symbol, let reason):
            return "Failed to calculate spread for \(symbol): \(reason)"
        case .insufficientBalance(let required, let available):
            return "Insufficient balance (required: \(required), available: \(available))"
        case .invalidState(let component, let expected, let actual):
            return "Invalid state in \(component) (expected: \(expected), actual: \(actual))"
        case .operationNotAllowed(let component, let operation, let reason):
            return "Operation '\(operation)' not allowed in \(component): \(reason)"
        case .internalError(let component, let reason):
            return "Internal error in \(component): \(reason)"
        }
    }

    public var logData: [String: String] {
        var data: [String: String] = ["error_type": "logic"]

        switch self {
        case .invalidConfiguration(let field, let reason):
            data["field"] = field
            data["reason"] = reason
            data["error"] = "invalid_configuration"
        case .spreadCalculationFailed(let symbol, let reason):
            data["symbol"] = symbol
            data["reason"] = reason
            data["error"] = "spread_calculation_failed"
        case .insufficientBalance(let required, let available):
            data["required"] = NSDecimalNumber(decimal: required).stringValue
            data["available"] = NSDecimalNumber(decimal: available).stringValue
            data["error"] = "insufficient_balance"
        case .invalidState(let component, let expected, let actual):
            data["component"] = component
            data["expected"] = expected
            data["actual"] = actual
            data["error"] = "invalid_state"
        case .operationNotAllowed(let component, let operation, let reason):
            data["component"] = component
            data["operation"] = operation
            data["reason"] = reason
            data["error"] = "operation_not_allowed"
        case .internalError(let component, let reason):
            data["component"] = component
            data["reason"] = reason
            data["error"] = "internal_error"
        }

        return data
    }
}

extension StructuredLogger {
    public func logError(_ error: ArbitrageError, component: String, correlationId: String? = nil) {
        var data = error.logData
        data["description"] = error.localizedDescription
        self.error(component: component, event: "arbitrage_error", data: data, correlationId: correlationId)
    }
}
