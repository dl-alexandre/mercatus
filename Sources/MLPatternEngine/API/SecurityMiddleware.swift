import Foundation
import CommonCrypto
import Utils

public protocol SecurityMiddlewareProtocol {
    func authenticate(request: APIRequest) async throws -> AuthResult
    func authorize(request: APIRequest, user: AuthenticatedUser) async throws -> Bool
    func validateRateLimit(request: APIRequest) async throws -> Bool
    func addSecurityHeaders(response: inout APIResponse) async throws
    func validateInput(request: APIRequest) async throws -> Bool
}

public struct APIRequest {
    public let path: String
    public let method: String
    public let headers: [String: String]
    public let queryParams: [String: String]
    public let body: Data?
    public let clientIP: String
    public let userAgent: String?
    public let timestamp: Date

    public init(path: String, method: String, headers: [String: String], queryParams: [String: String], body: Data?, clientIP: String, userAgent: String?, timestamp: Date) {
        self.path = path
        self.method = method
        self.headers = headers
        self.queryParams = queryParams
        self.body = body
        self.clientIP = clientIP
        self.userAgent = userAgent
        self.timestamp = timestamp
    }
}

public struct APIResponse {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data?

    public init(statusCode: Int, headers: [String: String], body: Data?) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct AuthResult {
    public let isAuthenticated: Bool
    public let user: AuthenticatedUser?
    public let error: AuthError?

    public init(isAuthenticated: Bool, user: AuthenticatedUser?, error: AuthError?) {
        self.isAuthenticated = isAuthenticated
        self.user = user
        self.error = error
    }
}

public struct AuthenticatedUser {
    public let userId: String
    public let username: String
    public let permissions: [String]
    public let roles: [String]
    public let tokenExpiry: Date

    public init(userId: String, username: String, permissions: [String], roles: [String], tokenExpiry: Date) {
        self.userId = userId
        self.username = username
        self.permissions = permissions
        self.roles = roles
        self.tokenExpiry = tokenExpiry
    }
}

public enum AuthError: Error {
    case invalidToken
    case tokenExpired
    case insufficientPermissions
    case invalidCredentials
    case accountLocked
    case rateLimitExceeded
}

public class SecurityMiddleware: SecurityMiddlewareProtocol {
    private let authManager: AuthManager
    private let rateLimiter: RateLimiter
    private let inputValidator: InputValidator
    private let logger: StructuredLogger

    public init(authManager: AuthManager, rateLimiter: RateLimiter, inputValidator: InputValidator, logger: StructuredLogger) {
        self.authManager = authManager
        self.rateLimiter = rateLimiter
        self.inputValidator = inputValidator
        self.logger = logger
    }

    public func authenticate(request: APIRequest) async throws -> AuthResult {
        guard let authHeader = request.headers["Authorization"] else {
            logger.warn(component: "SecurityMiddleware", event: "Missing authorization header", data: [
                "path": request.path,
                "clientIP": request.clientIP
            ])
            return AuthResult(isAuthenticated: false, user: nil, error: .invalidToken)
        }

        let token = extractToken(from: authHeader)
        guard let token = token else {
            logger.warn(component: "SecurityMiddleware", event: "Invalid authorization header format", data: [
                "path": request.path,
                "clientIP": request.clientIP
            ])
            return AuthResult(isAuthenticated: false, user: nil, error: .invalidToken)
        }

        do {
            let user = try await authManager.validateTokenAndGetUser(token)
            logger.info(component: "SecurityMiddleware", event: "User authenticated successfully", data: [
                "userId": user.userId,
                "username": user.username,
                "path": request.path
            ])
            return AuthResult(isAuthenticated: true, user: user, error: nil)
        } catch {
            logger.warn(component: "SecurityMiddleware", event: "Authentication failed", data: [
                "error": error.localizedDescription,
                "path": request.path,
                "clientIP": request.clientIP
            ])
            return AuthResult(isAuthenticated: false, user: nil, error: .invalidToken)
        }
    }

    public func authorize(request: APIRequest, user: AuthenticatedUser) async throws -> Bool {
        let requiredPermission = getRequiredPermission(for: request.path, method: request.method)

        guard let permission = requiredPermission else {
            return true
        }

        let hasPermission = user.permissions.contains(permission) || user.roles.contains("admin")

        if !hasPermission {
            logger.warn(component: "SecurityMiddleware", event: "Authorization failed", data: [
                "userId": user.userId,
                "requiredPermission": permission,
                "userPermissions": user.permissions.joined(separator: ","),
                "path": request.path
            ])
        }

        return hasPermission
    }

    public func validateRateLimit(request: APIRequest) async throws -> Bool {
        let identifier = getRateLimitIdentifier(request: request)
        let isAllowed = try await rateLimiter.checkLimit(for: identifier)

        if !isAllowed {
            logger.warn(component: "SecurityMiddleware", event: "Rate limit exceeded", data: [
                "identifier": identifier,
                "path": request.path,
                "clientIP": request.clientIP
            ])
        }

        return isAllowed
    }

    public func addSecurityHeaders(response: inout APIResponse) async throws {
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    }

    public func validateInput(request: APIRequest) async throws -> Bool {
        do {
            return try await inputValidator.validate(request: request)
        } catch {
            throw APIError.invalidInput
        }
    }

    private func extractToken(from authHeader: String) -> String? {
        let components = authHeader.split(separator: " ")
        guard components.count == 2, components[0] == "Bearer" else {
            return nil
        }
        return String(components[1])
    }

    private func getRequiredPermission(for path: String, method: String) -> String? {
        switch (path, method) {
        case ("/api/v1/predict", "POST"):
            return "predict"
        case ("/api/v1/predict/batch", "POST"):
            return "predict"
        case ("/api/v1/patterns/detect", "POST"):
            return "patterns"
        case ("/api/v1/health", "GET"):
            return nil
        case ("/api/v1/models", "GET"):
            return "models"
        case ("/api/v1/metrics", "GET"):
            return "metrics"
        default:
            return "read"
        }
    }

    private func getRateLimitIdentifier(request: APIRequest) -> String {
        if let userId = extractUserId(from: request) {
            return "user:\(userId)"
        } else {
            return "ip:\(request.clientIP)"
        }
    }

    private func extractUserId(from request: APIRequest) -> String? {
        guard let authHeader = request.headers["Authorization"],
              let token = extractToken(from: authHeader) else {
            return nil
        }

        return authManager.extractUserId(from: token)
    }
}

public class AuthManager {
    private let jwtSecret: String
    private let tokenExpiry: TimeInterval
    private let logger: StructuredLogger

    public init(jwtSecret: String, tokenExpiry: TimeInterval = 3600, logger: StructuredLogger) {
        self.jwtSecret = jwtSecret
        self.tokenExpiry = tokenExpiry
        self.logger = logger
    }

    public func generateToken(for username: String) -> String {
        let payload: [String: Any] = [
            "username": username,
            "exp": Int(Date().addingTimeInterval(tokenExpiry).timeIntervalSince1970),
            "iat": Int(Date().timeIntervalSince1970)
        ]

        return createJWT(payload: payload)
    }

    public func validateToken(_ token: String) -> Bool {
        do {
            let payload = try decodeJWT(token: token)
            guard let exp = payload["exp"] as? Int else { return false }

            let expiryDate = Date(timeIntervalSince1970: TimeInterval(exp))
            return expiryDate > Date()
        } catch {
            return false
        }
    }

    public func validateTokenAndGetUser(_ token: String) async throws -> AuthenticatedUser {
        let payload = try decodeJWT(token: token)

        guard let username = payload["username"] as? String,
              let exp = payload["exp"] as? Int else {
            throw AuthError.invalidToken
        }

        let expiryDate = Date(timeIntervalSince1970: TimeInterval(exp))
        guard expiryDate > Date() else {
            throw AuthError.tokenExpired
        }

        let user = try await getUserByUsername(username)
        return user
    }

    public func extractUserId(from token: String) -> String? {
        do {
            let payload = try decodeJWT(token: token)
            return payload["username"] as? String
        } catch {
            return nil
        }
    }

    private func createJWT(payload: [String: Any]) -> String {
        let header = ["alg": "HS256", "typ": "JWT"]

        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)

        let headerBase64 = headerData.base64EncodedString()
        let payloadBase64 = payloadData.base64EncodedString()

        let signature = createSignature(header: headerBase64, payload: payloadBase64)

        return "\(headerBase64).\(payloadBase64).\(signature)"
    }

    private func decodeJWT(token: String) throws -> [String: Any] {
        let components = token.split(separator: ".")
        guard components.count == 3 else {
            throw AuthError.invalidToken
        }

        let payloadData = Data(base64Encoded: String(components[1]))!
        let payload = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]

        return payload
    }

    private func createSignature(header: String, payload: String) -> String {
        let data = "\(header).\(payload)".data(using: .utf8)!
        let signature = data.hmac(algorithm: .sha256, key: jwtSecret)
        return signature.base64EncodedString()
    }

    private func getUserByUsername(_ username: String) async throws -> AuthenticatedUser {
        let mockUsers: [String: AuthenticatedUser] = [
            "admin": AuthenticatedUser(
                userId: "admin-1",
                username: "admin",
                permissions: ["predict", "patterns", "models", "metrics", "admin"],
                roles: ["admin"],
                tokenExpiry: Date().addingTimeInterval(tokenExpiry)
            ),
            "user": AuthenticatedUser(
                userId: "user-1",
                username: "user",
                permissions: ["predict", "patterns"],
                roles: ["user"],
                tokenExpiry: Date().addingTimeInterval(tokenExpiry)
            )
        ]

        guard let user = mockUsers[username] else {
            throw AuthError.invalidCredentials
        }

        return user
    }
}

public class InputValidator {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func validate(request: APIRequest) async throws -> Bool {
        if let body = request.body {
            try validateRequestBody(body)
        }

        try validateQueryParams(request.queryParams)
        try validateHeaders(request.headers)

        return true
    }

    private func validateRequestBody(_ body: Data) throws {
        guard body.count <= 10_000_000 else {
            throw ValidationError.bodyTooLarge
        }

        if let json = try? JSONSerialization.jsonObject(with: body) {
            try validateJSONObject(json)
        }
    }

    private func validateQueryParams(_ params: [String: String]) throws {
        for (key, value) in params {
            guard key.count <= 100 else {
                throw ValidationError.invalidQueryParam
            }
            guard value.count <= 1000 else {
                throw ValidationError.invalidQueryParam
            }
        }
    }

    private func validateHeaders(_ headers: [String: String]) throws {
        for (key, value) in headers {
            guard key.count <= 100 else {
                throw ValidationError.invalidHeader
            }
            guard value.count <= 1000 else {
                throw ValidationError.invalidHeader
            }
        }
    }

    private func validateJSONObject(_ object: Any) throws {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                guard key.count <= 100 else {
                    throw ValidationError.invalidJSONKey
                }
                try validateJSONValue(value)
            }
        }
    }

    private func validateJSONValue(_ value: Any) throws {
        if let string = value as? String {
            guard string.count <= 10000 else {
                throw ValidationError.invalidJSONValue
            }
        } else if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            if doubleValue.isNaN || doubleValue.isInfinite {
                throw ValidationError.invalidJSONValue
            }
        } else if let array = value as? [Any] {
            guard array.count <= 1000 else {
                throw ValidationError.invalidJSONValue
            }
            for item in array {
                try validateJSONValue(item)
            }
        } else if let dict = value as? [String: Any] {
            try validateJSONObject(dict)
        }
    }
}

public enum ValidationError: Error {
    case bodyTooLarge
    case invalidQueryParam
    case invalidHeader
    case invalidJSONKey
    case invalidJSONValue
}

extension Data {
    func hmac(algorithm: HMACAlgorithm, key: String) -> Data {
        let cKey = key.cString(using: String.Encoding.utf8)!
        let cData = self.withUnsafeBytes { bytes in
            return bytes.bindMemory(to: UInt8.self)
        }
        var result = [UInt8](repeating: 0, count: Int(algorithm.digestLength))
        CCHmac(algorithm.algorithm, cKey, strlen(cKey), cData.baseAddress, self.count, &result)
        return Data(result)
    }
}

enum HMACAlgorithm {
    case sha256

    var algorithm: CCHmacAlgorithm {
        switch self {
        case .sha256:
            return CCHmacAlgorithm(kCCHmacAlgSHA256)
        }
    }

    var digestLength: Int {
        switch self {
        case .sha256:
            return Int(CC_SHA256_DIGEST_LENGTH)
        }
    }
}
