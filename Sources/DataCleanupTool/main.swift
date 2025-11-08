import Foundation
import Utils
import MLPatternEngine

@main
struct DataCleanupTool {
    static func main() async throws {
        let logger = StructuredLogger()
        logger.info(component: "DataCleanupTool", event: "Starting data cleanup process")

        // Open the ML database
        let database = try SQLiteTimeSeriesDatabase(logger: logger)
        let qualityValidator = DataQualityValidator(logger: logger)

        // Step 1: Identify and remove invalid data points
        logger.info(component: "DataCleanupTool", event: "Step 1: Identifying invalid data points")

        let allSymbolsResult = try await database.executeQuery("SELECT DISTINCT symbol FROM market_data ORDER BY symbol;", parameters: [])
        var totalProcessed = 0
        var totalRemoved = 0

        for symbolRow in allSymbolsResult {
            guard let symbol = symbolRow["symbol"] as? String else { continue }

            logger.info(component: "DataCleanupTool", event: "Processing symbol", data: ["symbol": symbol])

            // Get all data points for this symbol
            let dataPoints = try await database.getMarketData(symbol: symbol, from: Date.distantPast, to: Date.distantFuture)
            var validPoints: [MarketDataPoint] = []
            var removedCount = 0

            for point in dataPoints {
                let qualityResult = qualityValidator.validateDataPoint(point)
                if qualityResult.isValid {
                    validPoints.append(point)
                } else {
                    removedCount += 1
                    logger.debug(component: "DataCleanupTool", event: "Removing invalid data point", data: [
                        "symbol": symbol,
                        "timestamp": String(point.timestamp.timeIntervalSince1970)
                    ])
                }
            }

            // Clear existing data for this symbol
            _ = try await database.executeUpdate("DELETE FROM market_data WHERE symbol = ?;", parameters: [symbol])

            // Re-insert only valid data
            if !validPoints.isEmpty {
                try await database.insertMarketData(validPoints)
            }

            totalProcessed += dataPoints.count
            totalRemoved += removedCount

            logger.info(component: "DataCleanupTool", event: "Symbol cleanup completed", data: [
                "symbol": symbol,
                "original_count": String(dataPoints.count),
                "valid_count": String(validPoints.count),
                "removed_count": String(removedCount)
            ])
        }

        // Step 2: Remove duplicate entries (in case any slipped through)
        logger.info(component: "DataCleanupTool", event: "Step 2: Removing any remaining duplicates")

        let dedupeSQL = """
        DELETE FROM market_data
        WHERE id NOT IN (
            SELECT MIN(id)
            FROM market_data
            GROUP BY symbol, timestamp
        );
        """

        let duplicatesRemoved = try await database.executeUpdate(dedupeSQL, parameters: [])
        totalRemoved += duplicatesRemoved

        // Step 3: Validate pattern detection data
        logger.info(component: "DataCleanupTool", event: "Step 3: Validating pattern detection data")

        // Fix confidence scores > 1.0
        let fixConfidenceSQL = """
        UPDATE detected_patterns
        SET confidence = 1.0
        WHERE confidence > 1.0;
        """

        let confidenceFixed = try await database.executeUpdate(fixConfidenceSQL, parameters: [])
        if confidenceFixed > 0 {
            logger.info(component: "DataCleanupTool", event: "Fixed confidence scores", data: ["count": String(confidenceFixed)])
        }

        // Step 4: Generate cleanup statistics
        logger.info(component: "DataCleanupTool", event: "Step 4: Generating cleanup statistics")

        let finalStats = try await database.executeQuery("""
            SELECT
                COUNT(*) as total_points,
                COUNT(DISTINCT symbol) as unique_symbols,
                AVG(timestamp) as avg_timestamp,
                MIN(timestamp) as min_timestamp,
                MAX(timestamp) as max_timestamp
            FROM market_data;
        """, parameters: [])

        if let stats = finalStats.first {
            logger.info(component: "DataCleanupTool", event: "Final database statistics", data: [
                "total_points": String(stats["total_points"] as? Int ?? 0),
                "unique_symbols": String(stats["unique_symbols"] as? Int ?? 0),
                "data_span_days": String(((stats["max_timestamp"] as? Double ?? 0) - (stats["min_timestamp"] as? Double ?? 0)) / 86400)
            ])
        }

        // Step 5: Validate data integrity
        logger.info(component: "DataCleanupTool", event: "Step 5: Validating data integrity")

        let integrityChecks = try await database.executeQuery("""
            SELECT
                symbol,
                COUNT(*) as point_count,
                COUNT(DISTINCT timestamp) as unique_timestamps,
                (COUNT(*) - COUNT(DISTINCT timestamp)) as duplicates
            FROM market_data
            GROUP BY symbol
            HAVING duplicates > 0
            ORDER BY duplicates DESC
            LIMIT 5;
        """, parameters: [])

        if integrityChecks.isEmpty {
            logger.info(component: "DataCleanupTool", event: "✅ Data integrity validation passed - no duplicates found")
        } else {
            logger.error(component: "DataCleanupTool", event: "❌ Data integrity issues still exist", data: [
                "symbols_with_duplicates": String(integrityChecks.count)
            ])
        }

        // Final summary
        logger.info(component: "DataCleanupTool", event: "Data cleanup completed", data: [
            "total_processed": String(totalProcessed),
            "total_removed": String(totalRemoved),
            "removal_rate": String(format: "%.1f%%", Double(totalRemoved) / Double(totalProcessed) * 100)
        ])

        print("🎉 Data cleanup completed successfully!")
        print("📊 Summary: Processed \(totalProcessed) points, removed \(totalRemoved) invalid points")
    }
}
