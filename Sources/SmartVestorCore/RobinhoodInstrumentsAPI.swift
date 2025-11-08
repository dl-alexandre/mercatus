import Foundation
import Utils

public actor RobinhoodInstrumentsAPI {
    public static let shared = RobinhoodInstrumentsAPI()

    private var cachedSymbols: [String]? = nil
    private var lastFetch: Date? = nil
    private let cacheTTL: TimeInterval = 6 * 60 * 60

    private static func findProjectRoot() -> String? {
        let fileManager = FileManager.default
        var currentPath = fileManager.currentDirectoryPath

        while !currentPath.isEmpty && currentPath != "/" {
            let packageSwiftPath = (currentPath as NSString).appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageSwiftPath) {
                return currentPath
            }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }

        return fileManager.currentDirectoryPath
    }

    private static func loadEnvFileIfNeeded() {
        let projectRoot = findProjectRoot() ?? FileManager.default.currentDirectoryPath
        let envPaths = [
            (projectRoot as NSString).appendingPathComponent(".env"),
            (projectRoot as NSString).appendingPathComponent("config/production.env")
        ]
        for envPath in envPaths {
            guard let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) else {
                continue
            }

            for line in envContent.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    var value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))

                    if (key == "ROBINHOOD_API_KEY" || key == "ROBINHOOD_PRIVATE_KEY") && ProcessInfo.processInfo.environment[key] == nil {
                        setenv(key, value, 1)
                    }
                }
            }

            if ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"] != nil {
                break
            }
        }
    }

    public func fetchSupportedSymbols(logger: StructuredLogger, forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh, let last = lastFetch, let cached = cachedSymbols, Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }

        Self.loadEnvFileIfNeeded()

        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"] else {
            logger.warn(component: "RobinhoodInstrumentsAPI", event: "api_key_missing", data: ["message": "ROBINHOOD_API_KEY not set in environment or .env file"])
            throw RobinhoodInstrumentsAPIError.apiKeyMissing
        }

        guard let privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"] else {
            logger.warn(component: "RobinhoodInstrumentsAPI", event: "private_key_missing", data: ["message": "ROBINHOOD_PRIVATE_KEY not set in environment or .env file"])
            throw RobinhoodInstrumentsAPIError.apiKeyMissing
        }

        guard let privateKey = Data(base64Encoded: privateKeyBase64) else {
            logger.warn(component: "RobinhoodInstrumentsAPI", event: "private_key_invalid", data: [
                "message": "ROBINHOOD_PRIVATE_KEY is not valid base64",
                "key_length": String(privateKeyBase64.count)
            ])
            throw RobinhoodInstrumentsAPIError.apiKeyMissing
        }

        logger.debug(component: "RobinhoodInstrumentsAPI", event: "credentials_loaded", data: [
            "api_key_set": "true",
            "private_key_set": "true",
            "private_key_length": String(privateKey.count)
        ])

        logger.info(component: "RobinhoodInstrumentsAPI", event: "discovering_symbols", data: ["method": "quotes_endpoint_batch"])

        let base = "https://trading.robinhood.com"
        let endpointPath = "/api/v1/crypto/marketdata/quotes/"

        let knownSymbols = [
            "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
            "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
            "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
            "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
            "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
            "VIRTUAL", "ZORA", "DOT", "MATIC", "BAT", "LRC", "YFI",
            "SUSHI", "MKR", "SNX", "1INCH", "BSV", "ALGO", "ATOM", "NEAR",
            "FTM", "ICP", "GRT", "FIL", "MANA", "SAND", "AXS", "ENJ"
        ]

        let pairs = knownSymbols.map { "\($0)-USD" }
        let symbolsParam = pairs.joined(separator: ",")

        var components = URLComponents(string: "\(base)\(endpointPath)")!
        components.queryItems = [URLQueryItem(name: "symbols", value: symbolsParam)]
        guard let url = components.url else {
            throw RobinhoodInstrumentsAPIError.invalidURL
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let method = "GET"
        let message = "\(apiKey)\(timestamp)\(endpointPath)\(method)"
        let messageData = message.data(using: .utf8)!
        let signature = try Self.signMessage(messageData, privateKey: privateKey)
        let signatureBase64 = signature.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(signatureBase64, forHTTPHeaderField: "x-signature")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RobinhoodInstrumentsAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "Unable to decode"
            logger.warn(component: "RobinhoodInstrumentsAPI", event: "http_error", data: [
                "status": String(http.statusCode),
                "response": errorBody
            ])
            throw RobinhoodInstrumentsAPIError.httpError(statusCode: http.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw RobinhoodInstrumentsAPIError.invalidJSON
        }

        var availableSymbols: Set<String> = []
        for quote in results {
            if let symbol = quote["symbol"] as? String {
                let baseSymbol = symbol.replacingOccurrences(of: "-USD", with: "")
                availableSymbols.insert(baseSymbol)
            }
        }

        if availableSymbols.isEmpty {
            logger.warn(component: "RobinhoodInstrumentsAPI", event: "discovery_failed_completely", data: [
                "message": "Could not discover any tradable symbols via instruments endpoint. This may indicate API issues.",
                "instruments_count": String(results.count)
            ])
            return []
        }

        let list = Array(availableSymbols).sorted()
        cachedSymbols = list
        lastFetch = Date()
        logger.info(component: "RobinhoodInstrumentsAPI", event: "symbols_discovered", data: [
            "count": String(list.count),
            "method": "dynamic_discovery"
        ])
        return list
    }

    private static func signMessage(_ message: Data, privateKey: Data) throws -> Data {
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let scriptPath = "\(currentDirectory)/scripts/sign_robinhood_request.py"

        guard fileManager.fileExists(atPath: scriptPath) else {
            throw RobinhoodInstrumentsAPIError.signingFailed("Signing script not found at \(scriptPath)")
        }

        let messageBase64 = message.base64EncodedString()
        let privateKeyBase64 = privateKey.base64EncodedString()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
        process.arguments = [scriptPath, "--message", messageBase64, "--private-key", privateKeyBase64]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw RobinhoodInstrumentsAPIError.signingFailed("Python signing script failed with exit code \(process.terminationStatus). Output: \(output)")
        }

        let signatureBase64 = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw RobinhoodInstrumentsAPIError.signingFailed("Failed to decode signature from script output")
        }

        return signature
    }
}

public enum RobinhoodInstrumentsAPIError: Error, LocalizedError {
    case apiKeyMissing
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case invalidJSON
    case emptyResponse
    case fetchFailed(String)
    case signingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ROBINHOOD_API_KEY environment variable is not set"
        case .invalidURL:
            return "Failed to construct API URL"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidJSON:
            return "Failed to parse JSON response"
        case .emptyResponse:
            return "API returned empty symbol list"
        case .fetchFailed(let message):
            return "Failed to fetch symbols: \(message)"
        case .signingFailed(let message):
            return "Failed to sign request: \(message)"
        }
    }
}
