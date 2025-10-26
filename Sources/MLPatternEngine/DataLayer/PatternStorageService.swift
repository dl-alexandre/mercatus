import Foundation
import Core
import Utils

public protocol PatternStorageProtocol {
    func storePattern(_ pattern: DetectedPattern) async throws
    func storePatterns(_ patterns: [DetectedPattern]) async throws
    func getPatterns(symbol: String?, patternType: DetectedPattern.PatternType?, from: Date?, to: Date?, minConfidence: Double?) async throws -> [DetectedPattern]
    func getPatternsByConfidence(minConfidence: Double, limit: Int?) async throws -> [DetectedPattern]
    func getPatternsByType(_ patternType: DetectedPattern.PatternType, limit: Int?) async throws -> [DetectedPattern]
    func deleteOldPatterns(olderThan: Date) async throws
    func getPatternCount(symbol: String?, patternType: DetectedPattern.PatternType?) async throws -> Int
}

public class PatternStorageService: PatternStorageProtocol {
    private let database: DatabaseProtocol
    private let logger: StructuredLogger

    public init(database: DatabaseProtocol, logger: StructuredLogger) {
        self.database = database
        self.logger = logger
    }

    public func storePattern(_ pattern: DetectedPattern) async throws {
        let insertQuery = """
        INSERT INTO detected_patterns (
            pattern_id, pattern_type, symbol, start_time, end_time,
            confidence, completion_score, price_target, stop_loss,
            market_conditions, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let marketConditions = try encodeMarketConditions(pattern.marketConditions)

        let parameters: [any Sendable] = [
            pattern.patternId,
            pattern.patternType.rawValue,
            pattern.symbol,
            pattern.startTime.timeIntervalSince1970,
            pattern.endTime.timeIntervalSince1970,
            pattern.confidence,
            pattern.completionScore,
            pattern.priceTarget as any Sendable,
            pattern.stopLoss as any Sendable,
            marketConditions,
            Date().timeIntervalSince1970
        ]
        _ = try await database.executeUpdate(insertQuery, parameters: parameters)

        logger.debug(component: "PatternStorageService", event: "Stored pattern", data: [
            "patternId": pattern.patternId,
            "patternType": pattern.patternType.rawValue,
            "symbol": pattern.symbol,
            "confidence": String(pattern.confidence)
        ])
    }

    public func storePatterns(_ patterns: [DetectedPattern]) async throws {
        guard !patterns.isEmpty else { return }

        let insertQuery = """
        INSERT INTO detected_patterns (
            pattern_id, pattern_type, symbol, start_time, end_time,
            confidence, completion_score, price_target, stop_loss,
            market_conditions, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        for pattern in patterns {
            let marketConditions = try encodeMarketConditions(pattern.marketConditions)

            let parameters: [any Sendable] = [
                pattern.patternId,
                pattern.patternType.rawValue,
                pattern.symbol,
                pattern.startTime.timeIntervalSince1970,
                pattern.endTime.timeIntervalSince1970,
                pattern.confidence,
                pattern.completionScore,
                pattern.priceTarget as any Sendable,
                pattern.stopLoss as any Sendable,
                marketConditions,
                Date().timeIntervalSince1970
            ]
            _ = try await database.executeUpdate(insertQuery, parameters: parameters)
        }

        logger.info(component: "PatternStorageService", event: "Stored \(patterns.count) patterns")
    }

    public func getPatterns(
        symbol: String? = nil,
        patternType: DetectedPattern.PatternType? = nil,
        from: Date? = nil,
        to: Date? = nil,
        minConfidence: Double? = nil
    ) async throws -> [DetectedPattern] {
        var query = """
        SELECT pattern_id, pattern_type, symbol, start_time, end_time,
               confidence, completion_score, price_target, stop_loss,
               market_conditions, created_at
        FROM detected_patterns
        WHERE 1=1
        """

        var parameters: [any Sendable] = []
        var parameterIndex = 1

        if let symbol = symbol {
            query += " AND symbol = ?"
            parameters.append(symbol)
            parameterIndex += 1
        }

        if let patternType = patternType {
            query += " AND pattern_type = ?"
            parameters.append(patternType.rawValue)
            parameterIndex += 1
        }

        if let from = from {
            query += " AND start_time >= ?"
            parameters.append(from.timeIntervalSince1970)
            parameterIndex += 1
        }

        if let to = to {
            query += " AND end_time <= ?"
            parameters.append(to.timeIntervalSince1970)
            parameterIndex += 1
        }

        if let minConfidence = minConfidence {
            query += " AND confidence >= ?"
            parameters.append(minConfidence)
            parameterIndex += 1
        }

        query += " ORDER BY created_at DESC"

        let sendableParameters: [any Sendable] = parameters
        let rows = try await database.executeQuery(query, parameters: sendableParameters)

        return try rows.compactMap { row -> DetectedPattern? in
            guard let patternId = row["pattern_id"] as? String,
                  let patternTypeString = row["pattern_type"] as? String,
                  let patternType = DetectedPattern.PatternType(rawValue: patternTypeString),
                  let symbol = row["symbol"] as? String,
                  let startTime = row["start_time"] as? Double,
                  let endTime = row["end_time"] as? Double,
                  let confidence = row["confidence"] as? Double,
                  let completionScore = row["completion_score"] as? Double else {
                return nil
            }

            let priceTarget = row["price_target"] as? Double
            let stopLoss = row["stop_loss"] as? Double
            let marketConditionsString = row["market_conditions"] as? String
            let marketConditions = try decodeMarketConditions(marketConditionsString)

            return DetectedPattern(
                patternId: patternId,
                patternType: patternType,
                symbol: symbol,
                startTime: Date(timeIntervalSince1970: startTime),
                endTime: Date(timeIntervalSince1970: endTime),
                confidence: confidence,
                completionScore: completionScore,
                priceTarget: priceTarget,
                stopLoss: stopLoss,
                marketConditions: marketConditions ?? [:]
            )
        }
    }

    public func getPatternsByConfidence(minConfidence: Double, limit: Int? = nil) async throws -> [DetectedPattern] {
        var query = """
        SELECT pattern_id, pattern_type, symbol, start_time, end_time,
               confidence, completion_score, price_target, stop_loss,
               market_conditions, created_at
        FROM detected_patterns
        WHERE confidence >= ?
        ORDER BY confidence DESC
        """

        var parameters: [any Sendable] = [minConfidence]

        if let limit = limit {
            query += " LIMIT ?"
            parameters.append(limit)
        }

        let sendableParameters: [any Sendable] = parameters
        let rows = try await database.executeQuery(query, parameters: sendableParameters)
        return try parsePatternsFromRows(rows)
    }

    public func getPatternsByType(_ patternType: DetectedPattern.PatternType, limit: Int? = nil) async throws -> [DetectedPattern] {
        var query = """
        SELECT pattern_id, pattern_type, symbol, start_time, end_time,
               confidence, completion_score, price_target, stop_loss,
               market_conditions, created_at
        FROM detected_patterns
        WHERE pattern_type = ?
        ORDER BY created_at DESC
        """

        var parameters: [any Sendable] = [patternType.rawValue]

        if let limit = limit {
            query += " LIMIT ?"
            parameters.append(limit)
        }

        let sendableParameters: [any Sendable] = parameters
        let rows = try await database.executeQuery(query, parameters: sendableParameters)
        return try parsePatternsFromRows(rows)
    }

    public func deleteOldPatterns(olderThan: Date) async throws {
        let deleteQuery = "DELETE FROM detected_patterns WHERE created_at < ?"
        let deletedCount = try await database.executeUpdate(deleteQuery, parameters: [olderThan.timeIntervalSince1970])
        logger.info(component: "PatternStorageService", event: "Deleted \(deletedCount) old patterns")
    }

    public func getPatternCount(symbol: String? = nil, patternType: DetectedPattern.PatternType? = nil) async throws -> Int {
        var query = "SELECT COUNT(*) as count FROM detected_patterns WHERE 1=1"
        var parameters: [any Sendable] = []

        if let symbol = symbol {
            query += " AND symbol = ?"
            parameters.append(symbol)
        }

        if let patternType = patternType {
            query += " AND pattern_type = ?"
            parameters.append(patternType.rawValue)
        }

        let sendableParameters: [any Sendable] = parameters
        let rows = try await database.executeQuery(query, parameters: sendableParameters)
        return (rows.first?["count"] as? Int) ?? 0
    }

    // MARK: - Private Methods

    private func parsePatternsFromRows(_ rows: [[String: any Sendable]]) throws -> [DetectedPattern] {
        return try rows.compactMap { row -> DetectedPattern? in
            guard let patternId = row["pattern_id"] as? String,
                  let patternTypeString = row["pattern_type"] as? String,
                  let patternType = DetectedPattern.PatternType(rawValue: patternTypeString),
                  let symbol = row["symbol"] as? String,
                  let startTime = row["start_time"] as? Double,
                  let endTime = row["end_time"] as? Double,
                  let confidence = row["confidence"] as? Double,
                  let completionScore = row["completion_score"] as? Double else {
                return nil
            }

            let priceTarget = row["price_target"] as? Double
            let stopLoss = row["stop_loss"] as? Double
            let marketConditionsString = row["market_conditions"] as? String
            let marketConditions = try decodeMarketConditions(marketConditionsString)

            return DetectedPattern(
                patternId: patternId,
                patternType: patternType,
                symbol: symbol,
                startTime: Date(timeIntervalSince1970: startTime),
                endTime: Date(timeIntervalSince1970: endTime),
                confidence: confidence,
                completionScore: completionScore,
                priceTarget: priceTarget,
                stopLoss: stopLoss,
                marketConditions: marketConditions ?? [:]
            )
        }
    }

    private func encodeMarketConditions(_ conditions: [String: String]?) throws -> String {
        guard let conditions = conditions else { return "" }

        let jsonData = try JSONSerialization.data(withJSONObject: conditions)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    private func decodeMarketConditions(_ jsonString: String?) throws -> [String: String]? {
        guard let jsonString = jsonString, !jsonString.isEmpty else { return nil }

        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
