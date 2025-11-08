import Foundation
import Utils

public final class MultiProviderMarketDataProvider: MarketDataProviderProtocol, Sendable {
    private let logger: StructuredLogger
    private let session = URLSession.shared

    // API Keys for different providers
    private let coinGeckoAPIKey: String?
    private let coinMarketCapAPIKey: String?
    private let cryptoCompareAPIKey: String?
    private let binanceAPIKey: String?
    private let binanceSecretKey: String?
    private let coinbaseAPIKey: String?
    private let coinbaseSecretKey: String?

    // Provider preferences (in order of preference)
    private let providerOrder: [MarketDataProviderType]

    public enum MarketDataProviderType: String, CaseIterable, Sendable {
        case robinhood = "robinhood"
        case coinGecko = "coingecko"
        case coinMarketCap = "coinmarketcap"
        case cryptoCompare = "cryptocompare"
        case binance = "binance"
        case coinbase = "coinbase"
        case mock = "mock"
    }

    public init(
        coinGeckoAPIKey: String? = nil,
        coinMarketCapAPIKey: String? = nil,
        cryptoCompareAPIKey: String? = nil,
        binanceAPIKey: String? = nil,
        binanceSecretKey: String? = nil,
        coinbaseAPIKey: String? = nil,
        coinbaseSecretKey: String? = nil,
        providerOrder: [MarketDataProviderType] = [.robinhood, .coinGecko, .cryptoCompare, .binance, .coinMarketCap, .coinbase],
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.logger = logger
        // Try to get API keys from environment variables if not provided
        self.coinGeckoAPIKey = coinGeckoAPIKey ?? ProcessInfo.processInfo.environment["COINGECKO_API_KEY"]
        self.coinMarketCapAPIKey = coinMarketCapAPIKey ?? ProcessInfo.processInfo.environment["COINMARKETCAP_API_KEY"]
        self.cryptoCompareAPIKey = cryptoCompareAPIKey ?? ProcessInfo.processInfo.environment["CRYPTOCOMPARE_API_KEY"]
        self.binanceAPIKey = binanceAPIKey ?? ProcessInfo.processInfo.environment["BINANCE_API_KEY"]
        self.binanceSecretKey = binanceSecretKey ?? ProcessInfo.processInfo.environment["BINANCE_SECRET_KEY"]
        self.coinbaseAPIKey = coinbaseAPIKey ?? ProcessInfo.processInfo.environment["COINBASE_API_KEY"]
        self.coinbaseSecretKey = coinbaseSecretKey ?? ProcessInfo.processInfo.environment["COINBASE_SECRET_KEY"]
        self.providerOrder = providerOrder
    }

    public func getHistoricalData(startDate: Date, endDate: Date, symbols: [String]) async throws -> [String: [MarketDataPoint]] {
        var data: [String: [MarketDataPoint]] = [:]

        let batchSize = 10
        let batches = symbols.chunked(into: batchSize)

        for batch in batches {
            let batchResults = try await withThrowingTaskGroup(of: (String, [MarketDataPoint]?).self) { group in
                var batchData: [String: [MarketDataPoint]?] = [:]

                for symbol in batch {
                    group.addTask {
                        var lastError: Error?

                        for provider in self.providerOrder {
                            do {
                                guard !Task.isCancelled else {
                                    return (symbol, nil)
                                }

                                let points = try await self.getHistoricalDataFromProvider(provider, symbol: symbol, startDate: startDate, endDate: endDate)
                                self.logger.info(component: "MultiProviderMarketDataProvider", event: "Successfully got historical data", data: [
                                    "symbol": symbol,
                                    "provider": provider.rawValue
                                ])
                                return (symbol, points)
                            } catch {
                                lastError = error
                                guard !Task.isCancelled else {
                                    return (symbol, nil)
                                }
                                self.logger.warn(component: "MultiProviderMarketDataProvider", event: "Failed to get historical data from provider", data: [
                                    "symbol": symbol,
                                    "provider": provider.rawValue,
                                    "error": error.localizedDescription
                                ])
                            }
                        }

                        self.logger.error(component: "MultiProviderMarketDataProvider", event: "Failed to get historical data from all providers", data: [
                            "symbol": symbol,
                            "error": lastError?.localizedDescription ?? "Unknown error"
                        ])
                        return (symbol, nil)
                    }
                }

                for try await (symbol, points) in group {
                    batchData[symbol] = points
                }

                return batchData
            }

            for (symbol, points) in batchResults {
                if let points = points {
                    data[symbol] = points
                }
            }
        }

        return data
    }

    public func getCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        var lastError: Error?

        for provider in providerOrder {
            do {
                let prices = try await getCurrentPricesFromProvider(provider, symbols: symbols)
                if prices.isEmpty {
                    continue
                }
                return prices
            } catch {
                lastError = error
            }
        }

        logger.error(component: "MultiProviderMarketDataProvider", event: "Failed to get current prices from all providers", data: [
            "error": lastError?.localizedDescription ?? "Unknown error"
        ])
        throw lastError ?? MarketDataError.apiError("All providers failed")
    }

    public func getVolumeData(symbols: [String]) async throws -> [String: Double] {
        var lastError: Error?

        for provider in providerOrder {
            do {
                let volumes = try await getVolumeDataFromProvider(provider, symbols: symbols)
                logger.info(component: "MultiProviderMarketDataProvider", event: "Successfully got volume data", data: [
                    "provider": provider.rawValue,
                    "count": String(volumes.count)
                ])
                return volumes
            } catch {
                lastError = error
                logger.warn(component: "MultiProviderMarketDataProvider", event: "Failed to get volume data from provider", data: [
                    "provider": provider.rawValue,
                    "error": error.localizedDescription
                ])
            }
        }

        logger.error(component: "MultiProviderMarketDataProvider", event: "Failed to get volume data from all providers", data: [
            "error": lastError?.localizedDescription ?? "Unknown error"
        ])
        throw lastError ?? MarketDataError.apiError("All providers failed")
    }

    // MARK: - Provider Dispatch Methods

    private func getHistoricalDataFromProvider(_ provider: MarketDataProviderType, symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        switch provider {
        case .robinhood:
            return try await getRobinhoodHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .coinGecko:
            return try await getCoinGeckoHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .coinMarketCap:
            return try await getCoinMarketCapHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .cryptoCompare:
            return try await getCryptoCompareHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .binance:
            return try await getBinanceHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .coinbase:
            return try await getCoinbaseHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        case .mock:
            return try await getMockHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
        }
    }

    private func getCurrentPricesFromProvider(_ provider: MarketDataProviderType, symbols: [String]) async throws -> [String: Double] {
        switch provider {
        case .robinhood:
            return try await getRobinhoodCurrentPrices(symbols: symbols)
        case .coinGecko:
            return try await getCoinGeckoCurrentPrices(symbols: symbols)
        case .coinMarketCap:
            return try await getCoinMarketCapCurrentPrices(symbols: symbols)
        case .cryptoCompare:
            return try await getCryptoCompareCurrentPrices(symbols: symbols)
        case .binance:
            return try await getBinanceCurrentPrices(symbols: symbols)
        case .coinbase:
            return try await getCoinbaseCurrentPrices(symbols: symbols)
        case .mock:
            return try await getMockCurrentPrices(symbols: symbols)
        }
    }

    private func getVolumeDataFromProvider(_ provider: MarketDataProviderType, symbols: [String]) async throws -> [String: Double] {
        switch provider {
        case .robinhood:
            throw MarketDataError.apiError("Robinhood volume data not supported")
        case .coinGecko:
            return try await getCoinGeckoVolumeData(symbols: symbols)
        case .coinMarketCap:
            return try await getCoinMarketCapVolumeData(symbols: symbols)
        case .cryptoCompare:
            return try await getCryptoCompareVolumeData(symbols: symbols)
        case .binance:
            return try await getBinanceVolumeData(symbols: symbols)
        case .coinbase:
            return try await getCoinbaseVolumeData(symbols: symbols)
        case .mock:
            return try await getMockVolumeData(symbols: symbols)
        }
    }

    // MARK: - CryptoCompare API Implementation

    // MARK: - Robinhood Historical (daily candles, best-effort)

    private func getRobinhoodHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"] else {
            throw MarketDataError.apiError("ROBINHOOD_API_KEY required")
        }

        // Try a daily interval for USD pairs; fall back gracefully on any error
        var components = URLComponents(string: "https://trading.robinhood.com/api/v1/crypto/marketdata/candles/")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "\(symbol)-USD"),
            URLQueryItem(name: "interval", value: "day")
        ]

        guard let url = components.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(String(Int(Date().timeIntervalSince1970)), forHTTPHeaderField: "x-timestamp")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MarketDataError.apiError("Robinhood historical API error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketDataError.apiError("Invalid JSON from Robinhood historical endpoint")
        }

        var points: [MarketDataPoint] = []
        if let results = json["results"] as? [[String: Any]] {
            for item in results {
                guard let tsStr = item["begins_at"] as? String,
                      let closeStr = item["close_price"] as? String,
                      let highStr = item["high_price"] as? String,
                      let lowStr = item["low_price"] as? String,
                      let openStr = item["open_price"] as? String,
                      let volumeStr = item["volume"] as? String,
                      let close = Double(closeStr),
                      let high = Double(highStr),
                      let low = Double(lowStr),
                      let open = Double(openStr),
                      let volume = Double(volumeStr) else {
                    continue
                }

                if let ts = ISO8601DateFormatter().date(from: tsStr) {
                    if ts < startDate || ts > endDate { continue }
                    let point = MarketDataPoint(
                        timestamp: ts,
                        price: close,
                        volume: volume,
                        high: high,
                        low: low,
                        open: open,
                        close: close
                    )
                    points.append(point)
                }
            }
        }

        return points
    }

    // MARK: - Robinhood API Implementation (read-only quotes)

    private func getRobinhoodCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"] else {
            throw MarketDataError.apiError("ROBINHOOD_API_KEY required")
        }

        var result: [String: Double] = [:]

        for symbol in symbols {
            let pair = "\(symbol)-USD"
            var components = URLComponents(string: "https://trading.robinhood.com/api/v1/crypto/marketdata/quotes/")!
            components.queryItems = [URLQueryItem(name: "symbol", value: pair)]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(String(Int(Date().timeIntervalSince1970)), forHTTPHeaderField: "x-timestamp")

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let results = json["results"] as? [[String: Any]], let first = results.first {
                        if let priceStr = first["last_trade_price"] as? String, let p = Double(priceStr) {
                            result[symbol] = p
                            continue
                        }
                        if let markStr = first["mark_price"] as? String, let p = Double(markStr) {
                            result[symbol] = p
                            continue
                        }
                        if let price = first["last_trade_price"] as? Double {
                            result[symbol] = price
                            continue
                        }
                    }
                }
            } catch {
                // Skip symbol on error; fall through to other providers via caller
            }
        }

        return result
    }

    private func getCryptoCompareHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        let toTimestamp = Int(endDate.timeIntervalSince1970)

        var urlComponents = URLComponents(string: "https://min-api.cryptocompare.com/data/v2/histoday")!
        urlComponents.queryItems = [
            URLQueryItem(name: "fsym", value: symbol),
            URLQueryItem(name: "tsym", value: "USD"),
            URLQueryItem(name: "limit", value: "2000"),
            URLQueryItem(name: "toTs", value: String(toTimestamp))
        ]

        if let apiKey = cryptoCompareAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CryptoCompare API error")
        }

        let cryptoCompareResponse = try JSONDecoder().decode(CryptoCompareHistoricalResponse.self, from: data)

        var points: [MarketDataPoint] = []
        for dataPoint in cryptoCompareResponse.Data.Data {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(dataPoint.time))
            let point = MarketDataPoint(
                timestamp: timestamp,
                price: dataPoint.close,
                volume: dataPoint.volumeto,
                high: dataPoint.high,
                low: dataPoint.low,
                open: dataPoint.open,
                close: dataPoint.close
            )
            points.append(point)
        }

        return points
    }

    private func getCryptoCompareCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://min-api.cryptocompare.com/data/pricemulti")!
        urlComponents.queryItems = [
            URLQueryItem(name: "fsyms", value: symbolsString),
            URLQueryItem(name: "tsyms", value: "USD")
        ]

        if let apiKey = cryptoCompareAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CryptoCompare API error")
        }

        let cryptoCompareResponse = try JSONDecoder().decode([String: CryptoComparePriceData].self, from: data)

        var prices: [String: Double] = [:]
        for (symbol, priceData) in cryptoCompareResponse {
            prices[symbol] = priceData.USD
        }

        return prices
    }

    private func getCryptoCompareVolumeData(symbols: [String]) async throws -> [String: Double] {
        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://min-api.cryptocompare.com/data/pricemultifull")!
        urlComponents.queryItems = [
            URLQueryItem(name: "fsyms", value: symbolsString),
            URLQueryItem(name: "tsyms", value: "USD")
        ]

        if let apiKey = cryptoCompareAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CryptoCompare API error")
        }

        let cryptoCompareResponse = try JSONDecoder().decode(CryptoCompareFullResponse.self, from: data)

        var volumes: [String: Double] = [:]
        for (symbol, data) in cryptoCompareResponse.RAW {
            volumes[symbol] = data.USD.VOLUME24HOUR
        }

        return volumes
    }

    // MARK: - Binance API Implementation

    private func getBinanceHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        let startTime = Int(startDate.timeIntervalSince1970 * 1000)
        let endTime = Int(endDate.timeIntervalSince1970 * 1000)

        var urlComponents = URLComponents(string: "https://api.binance.com/api/v3/klines")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbol", value: "\(symbol)USDT"),
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "startTime", value: String(startTime)),
            URLQueryItem(name: "endTime", value: String(endTime)),
            URLQueryItem(name: "limit", value: "1000")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("Binance API error")
        }

        let klines = try JSONDecoder().decode([[String]].self, from: data)

        var points: [MarketDataPoint] = []
        for kline in klines {
            guard kline.count >= 6 else { continue }

            let timestamp = Date(timeIntervalSince1970: Double(kline[0])! / 1000)
            let open = Double(kline[1])!
            let high = Double(kline[2])!
            let low = Double(kline[3])!
            let close = Double(kline[4])!
            let volume = Double(kline[5])!

            let point = MarketDataPoint(
                timestamp: timestamp,
                price: close,
                volume: volume,
                high: high,
                low: low,
                open: open,
                close: close
            )
            points.append(point)
        }

        return points
    }

    private func getBinanceCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        let symbolsString = symbols.map { "\($0)USDT" }.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://api.binance.com/api/v3/ticker/price")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbols", value: "[\(symbolsString)]")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("Binance API error")
        }

        let binanceResponse = try JSONDecoder().decode([BinancePriceData].self, from: data)

        var prices: [String: Double] = [:]
        for priceData in binanceResponse {
            let symbol = String(priceData.symbol.dropLast(4)) // Remove "USDT" suffix
            prices[symbol] = Double(priceData.price)
        }

        return prices
    }

    private func getBinanceVolumeData(symbols: [String]) async throws -> [String: Double] {
        let symbolsString = symbols.map { "\($0)USDT" }.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbols", value: "[\(symbolsString)]")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("Binance API error")
        }

        let binanceResponse = try JSONDecoder().decode([Binance24hrData].self, from: data)

        var volumes: [String: Double] = [:]
        for data in binanceResponse {
            let symbol = String(data.symbol.dropLast(4)) // Remove "USDT" suffix
            volumes[symbol] = Double(data.volume ?? "0") ?? 0.0
        }

        return volumes
    }

    // MARK: - Coinbase API Implementation

    private func getCoinbaseHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        // Coinbase Pro API for historical data
        let startTime = startDate.ISO8601Format()
        let endTime = endDate.ISO8601Format()

        var urlComponents = URLComponents(string: "https://api.exchange.coinbase.com/products/\(symbol)-USD/candles")!
        urlComponents.queryItems = [
            URLQueryItem(name: "start", value: startTime),
            URLQueryItem(name: "end", value: endTime),
            URLQueryItem(name: "granularity", value: "86400") // 1 day
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("Coinbase API error")
        }

        let candles = try JSONDecoder().decode([[Double]].self, from: data)

        var points: [MarketDataPoint] = []
        for candle in candles {
            guard candle.count >= 6 else { continue }

            let timestamp = Date(timeIntervalSince1970: candle[0])
            let low = candle[1]
            let high = candle[2]
            let open = candle[3]
            let close = candle[4]
            let volume = candle[5]

            let point = MarketDataPoint(
                timestamp: timestamp,
                price: close,
                volume: volume,
                high: high,
                low: low,
                open: open,
                close: close
            )
            points.append(point)
        }

        return points
    }

    private func getCoinbaseCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        var prices: [String: Double] = [:]

        for symbol in symbols {
            let urlComponents = URLComponents(string: "https://api.exchange.coinbase.com/products/\(symbol)-USD/ticker")!

            guard let url = urlComponents.url else {
                throw MarketDataError.invalidURL
            }

            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                continue // Skip this symbol if it fails
            }

            let ticker = try JSONDecoder().decode(CoinbaseTickerData.self, from: data)
            prices[symbol] = Double(ticker.price)
        }

        return prices
    }

    private func getCoinbaseVolumeData(symbols: [String]) async throws -> [String: Double] {
        var volumes: [String: Double] = [:]

        for symbol in symbols {
            let urlComponents = URLComponents(string: "https://api.exchange.coinbase.com/products/\(symbol)-USD/stats")!

            guard let url = urlComponents.url else {
                throw MarketDataError.invalidURL
            }

            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                continue // Skip this symbol if it fails
            }

            let stats = try JSONDecoder().decode(CoinbaseStatsData.self, from: data)
            volumes[symbol] = Double(stats.volume ?? "0") ?? 0.0
        }

        return volumes
    }

    // MARK: - Mock Data Implementation (Fallback)

    private func getMockHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1

        var points: [MarketDataPoint] = []
        var currentDate = startDate
        var currentPrice = generateMockPrice(for: symbol)

        let symbolHash = abs(symbol.hashValue)
        let dateHash = Int(startDate.timeIntervalSince1970) % 1000

        for i in 0..<days {
            let daySeed = (symbolHash + dateHash + i) % 1000
            let change = (Double(daySeed) / 1000.0 - 0.5) * 0.02
            currentPrice *= (1.0 + change)

            let ohlcSeed = (symbolHash + i) % 1000
            let high = currentPrice * (1.0 + Double(ohlcSeed % 20) / 1000.0)
            let low = currentPrice * (1.0 - Double((ohlcSeed + 100) % 20) / 1000.0)
            let open = currentPrice * (1.0 + Double((ohlcSeed + 200) % 10) / 1000.0 - 0.005)
            let close = currentPrice

            let baseVolume = getBaseVolumeForSymbol(symbol)
            let volumeSeed = (symbolHash + i * 7) % 1000
            let volume = baseVolume * (0.8 + Double(volumeSeed) / 1000.0 * 0.4)

            let point = MarketDataPoint(
                timestamp: currentDate,
                price: currentPrice,
                volume: volume,
                high: high,
                low: low,
                open: open,
                close: close
            )

            points.append(point)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }

        return points
    }

    private func getMockCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        var prices: [String: Double] = [:]
        for symbol in symbols {
            prices[symbol] = generateMockPrice(for: symbol)
        }
        return prices
    }

    private func getMockVolumeData(symbols: [String]) async throws -> [String: Double] {
        var volumes: [String: Double] = [:]
        for symbol in symbols {
            volumes[symbol] = getBaseVolumeForSymbol(symbol)
        }
        return volumes
    }

    // MARK: - Helper Methods

    private func generateMockPrice(for symbol: String) -> Double {
        let basePrice: Double
        switch symbol {
        case "BTC": basePrice = 45000
        case "ETH": basePrice = 3000
        case "ADA": basePrice = 0.5
        case "DOT": basePrice = 8
        case "LINK": basePrice = 15
        case "SOL": basePrice = 100
        case "AVAX": basePrice = 30
        case "MATIC": basePrice = 1.0
        case "ARB": basePrice = 2.0
        case "OP": basePrice = 2.5
        case "ATOM": basePrice = 10
        case "NEAR": basePrice = 4
        case "FTM": basePrice = 0.4
        case "ALGO": basePrice = 0.2
        case "ICP": basePrice = 10
        case "UNI": basePrice = 8
        case "AAVE": basePrice = 100
        case "COMP": basePrice = 50
        case "MKR": basePrice = 2500
        case "SNX": basePrice = 3
        case "GRT": basePrice = 0.2
        case "DOGE": basePrice = 0.1
        case "SHIB": basePrice = 0.00002
        case "PEPE": basePrice = 0.000002
        case "FLOKI": basePrice = 0.00002
        case "BONK": basePrice = 0.00002
        case "WIF": basePrice = 2.0
        case "BOME": basePrice = 0.015
        case "POPCAT": basePrice = 0.75
        case "MEW": basePrice = 0.03
        case "MYRO": basePrice = 0.2
        default: basePrice = 50
        }

        let symbolHash = abs(symbol.hashValue)
        let variation = Double(symbolHash % 1000) / 1000.0 * 0.1
        return basePrice * (0.95 + variation)
    }

    private func getBaseVolumeForSymbol(_ symbol: String) -> Double {
        let baseVolume: Double
        switch symbol {
        case "BTC": baseVolume = 35_000_000_000
        case "ETH": baseVolume = 18_000_000_000
        case "SOL": baseVolume = 3_000_000_000
        case "ADA": baseVolume = 1_200_000_000
        case "DOT": baseVolume = 800_000_000
        case "LINK": baseVolume = 1_500_000_000
        case "UNI": baseVolume = 600_000_000
        case "AAVE": baseVolume = 400_000_000
        case "COMP": baseVolume = 300_000_000
        case "MKR": baseVolume = 200_000_000
        case "AVAX": baseVolume = 800_000_000
        case "MATIC": baseVolume = 500_000_000
        case "ARB": baseVolume = 700_000_000
        case "OP": baseVolume = 600_000_000
        case "DOGE": baseVolume = 300_000_000
        case "SHIB": baseVolume = 200_000_000
        case "PEPE": baseVolume = 100_000_000
        case "BONK": baseVolume = 80_000_000
        case "WIF": baseVolume = 120_000_000
        default: baseVolume = 50_000_000
        }

        let symbolHash = abs(symbol.hashValue)
        let variation = Double(symbolHash % 1000) / 1000.0 * 0.2
        return baseVolume * (0.9 + variation)
    }

    // MARK: - Existing CoinGecko and CoinMarketCap Methods (Reused from RealMarketDataProvider)

    private func getCoinGeckoHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        let coinId = try await getCoinGeckoId(for: symbol)
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart/range")!
        urlComponents.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "from", value: String(startTimestamp)),
            URLQueryItem(name: "to", value: String(endTimestamp))
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let marketChartResponse = try JSONDecoder().decode(CoinGeckoMarketChartResponse.self, from: data)

        var points: [MarketDataPoint] = []
        let prices = marketChartResponse.prices
        let volumes = marketChartResponse.total_volumes
        let marketCaps = marketChartResponse.market_caps

        for i in 0..<prices.count {
            guard i < volumes.count && i < marketCaps.count else { continue }
            guard prices[i].count >= 2, volumes[i].count >= 2, marketCaps[i].count >= 2 else { continue }

            let timestamp = Date(timeIntervalSince1970: prices[i][0] / 1000)
            let price = prices[i][1]
            let volume = volumes[i][1]
            _ = marketCaps[i][1]

            let point = MarketDataPoint(
                timestamp: timestamp,
                price: price,
                volume: volume,
                high: price * 1.02,
                low: price * 0.98,
                open: price * 1.01,
                close: price
            )
            points.append(point)
        }

        return points
    }

    private func getCoinGeckoCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        let coinIds = try await getCoinGeckoIds(for: symbols)
        let coinIdsString = coinIds.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: coinIdsString),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true")
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let priceResponse = try JSONDecoder().decode([String: CoinGeckoPriceData].self, from: data)

        var prices: [String: Double] = [:]
        for (coinId, priceData) in priceResponse {
            if let symbol = getSymbolFromCoinGeckoId(coinId) {
                prices[symbol] = priceData.usd
            }
        }

        return prices
    }

    private func getCoinGeckoVolumeData(symbols: [String]) async throws -> [String: Double] {
        let coinIds = try await getCoinGeckoIds(for: symbols)
        let coinIdsString = coinIds.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: coinIdsString),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_vol", value: "true")
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let volumeResponse = try JSONDecoder().decode([String: CoinGeckoVolumeData].self, from: data)

        var volumes: [String: Double] = [:]
        for (coinId, volumeData) in volumeResponse {
            if let symbol = getSymbolFromCoinGeckoId(coinId) {
                volumes[symbol] = volumeData.usd_24h_vol ?? 0.0
            }
        }

        return volumes
    }

    private func getCoinGeckoId(for symbol: String) async throws -> String {
        let symbolToIdMap: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "ADA": "cardano",
            "DOT": "polkadot",
            "LINK": "chainlink",
            "SOL": "solana",
            "AVAX": "avalanche-2",
            "MATIC": "matic-network",
            "ARB": "arbitrum",
            "OP": "optimism",
            "ATOM": "cosmos",
            "NEAR": "near",
            "FTM": "fantom",
            "ALGO": "algorand",
            "ICP": "internet-computer",
            "UNI": "uniswap",
            "AAVE": "aave",
            "COMP": "compound-governance-token",
            "MKR": "maker",
            "SNX": "havven",
            "GRT": "the-graph",
            "DOGE": "dogecoin",
            "SHIB": "shiba-inu",
            "PEPE": "pepe",
            "BONK": "bonk",
            "WIF": "dogwifcoin",
            "BOME": "book-of-meme",
            "POPCAT": "popcat",
            "MEW": "cat-in-a-dogs-world",
            "MYRO": "myro",
            "BAND": "band-protocol",
            "API3": "api3",
            "XMR": "monero",
            "ZEC": "zcash",
            "DASH": "dash",
            "FET": "fetch-ai",
            "AGIX": "singularitynet",
            "OCEAN": "ocean-protocol",
            "FIL": "filecoin",
            "AR": "arweave",
            "SC": "siacoin"
        ]

        guard let coinId = symbolToIdMap[symbol.uppercased()] else {
            throw MarketDataError.unsupportedSymbol(symbol)
        }

        return coinId
    }

    private func getCoinGeckoIds(for symbols: [String]) async throws -> [String] {
        var coinIds: [String] = []
        for symbol in symbols {
            let coinId = try await getCoinGeckoId(for: symbol)
            coinIds.append(coinId)
        }
        return coinIds
    }

    private func getSymbolFromCoinGeckoId(_ coinId: String) -> String? {
        let idToSymbolMap: [String: String] = [
            "bitcoin": "BTC",
            "ethereum": "ETH",
            "cardano": "ADA",
            "polkadot": "DOT",
            "chainlink": "LINK",
            "solana": "SOL",
            "avalanche-2": "AVAX",
            "matic-network": "MATIC",
            "arbitrum": "ARB",
            "optimism": "OP",
            "cosmos": "ATOM",
            "near": "NEAR",
            "fantom": "FTM",
            "algorand": "ALGO",
            "internet-computer": "ICP",
            "uniswap": "UNI",
            "aave": "AAVE",
            "compound-governance-token": "COMP",
            "maker": "MKR",
            "havven": "SNX",
            "the-graph": "GRT",
            "dogecoin": "DOGE",
            "shiba-inu": "SHIB",
            "pepe": "PEPE",
            "bonk": "BONK",
            "dogwifcoin": "WIF",
            "book-of-meme": "BOME",
            "popcat": "POPCAT",
            "cat-in-a-dogs-world": "MEW",
            "myro": "MYRO",
            "band-protocol": "BAND",
            "api3": "API3",
            "monero": "XMR",
            "zcash": "ZEC",
            "dash": "DASH",
            "fetch-ai": "FET",
            "singularitynet": "AGIX",
            "ocean-protocol": "OCEAN",
            "filecoin": "FIL",
            "arweave": "AR",
            "siacoin": "SC"
        ]

        return idToSymbolMap[coinId]
    }

    private func getCoinMarketCapHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        throw MarketDataError.apiError("CoinMarketCap historical data requires paid API. Please use CoinGecko.")
    }

    private func getCoinMarketCapCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        guard let apiKey = coinMarketCapAPIKey else {
            throw MarketDataError.apiError("CoinMarketCap API key required")
        }

        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbol", value: symbolsString),
            URLQueryItem(name: "convert", value: "USD")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinMarketCap API error")
        }

        let cmcResponse = try JSONDecoder().decode(CoinMarketCapResponse.self, from: data)

        var prices: [String: Double] = [:]
        for (symbol, data) in cmcResponse.data {
            prices[symbol] = data.quote.USD.price
        }

        return prices
    }

    private func getCoinMarketCapVolumeData(symbols: [String]) async throws -> [String: Double] {
        guard let apiKey = coinMarketCapAPIKey else {
            throw MarketDataError.apiError("CoinMarketCap API key required")
        }

        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbol", value: symbolsString),
            URLQueryItem(name: "convert", value: "USD")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinMarketCap API error")
        }

        let cmcResponse = try JSONDecoder().decode(CoinMarketCapResponse.self, from: data)

        var volumes: [String: Double] = [:]
        for (symbol, data) in cmcResponse.data {
            volumes[symbol] = data.quote.USD.volume_24h ?? 0.0
        }

        return volumes
    }
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Additional Data Models

struct CryptoCompareHistoricalResponse: Codable {
    let Data: CryptoCompareDataContainer
}

struct CryptoCompareDataContainer: Codable {
    let Data: [CryptoCompareDataPoint]
}

struct CryptoCompareDataPoint: Codable {
    let time: Int
    let high: Double
    let low: Double
    let open: Double
    let close: Double
    let volumefrom: Double
    let volumeto: Double
}

struct CryptoComparePriceData: Codable {
    let USD: Double
}

struct CryptoCompareFullResponse: Codable {
    let RAW: [String: CryptoCompareRawData]
}

struct CryptoCompareRawData: Codable {
    let USD: CryptoCompareUSDData
}

struct CryptoCompareUSDData: Codable {
    let VOLUME24HOUR: Double
}

struct BinancePriceData: Codable {
    let symbol: String
    let price: String
}

struct Binance24hrData: Codable {
    let symbol: String
    let volume: String?
}

struct CoinbaseTickerData: Codable {
    let price: String
}

struct CoinbaseStatsData: Codable {
    let volume: String?
}

struct CoinGeckoVolumeData: Codable {
    let usd_24h_vol: Double?
}
