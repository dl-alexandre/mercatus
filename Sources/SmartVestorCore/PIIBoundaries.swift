import Foundation
import CryptoKit

public struct UserIdentifier {
    public let saltedHash: String
    public let salt: String

    public init(userID: String) {
        let salt = UUID().uuidString
        self.salt = salt
        let combined = "\(salt):\(userID)".data(using: .utf8)!
        let hash = SHA256.hash(data: combined)
        self.saltedHash = Data(hash).map { String(format: "%02x", $0) }.joined()
    }

    public func verify(userID: String) -> Bool {
        let combined = "\(salt):\(userID)".data(using: .utf8)!
        let hash = SHA256.hash(data: combined)
        return Data(hash).hexString == saltedHash
    }
}

extension AccountMapping {
    public static func accountIDWithPIIProtection(
        exchange: String,
        asset: String,
        userIdentifier: UserIdentifier? = nil
    ) -> UUID {
        if let userID = userIdentifier {
            return accountID(exchange: exchange, asset: asset, userId: userID.saltedHash)
        }
        return accountID(exchange: exchange, asset: asset)
    }
}
