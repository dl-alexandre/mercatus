import Foundation
import CryptoKit

public struct SealedAccountMapping {
    public let mapping: String
    public let signature: String

    public init(mapping: String, signature: String) {
        self.mapping = mapping
        self.signature = signature
    }

    public func verify(secretKey: SymmetricKey) -> Bool {
        let data = Data(mapping.utf8)
        let signatureData = Data(hexString: signature) ?? Data()

        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: secretKey)
        return Data(hmac) == signatureData
    }
}

extension AccountMapping {
    public static func sealAccountMappingSchema(secretKey: SymmetricKey) -> SealedAccountMapping {
        let schema = """
        AccountMapping Schema:
        - Namespace: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
        - Format: [userId:]exchange:asset (lowercased)
        - Hash: SHA512, first 16 bytes
        - UUID version: 5
        """

        let data = Data(schema.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: secretKey)
        let signature = Data(hmac).map { String(format: "%02x", $0) }.joined()

        return SealedAccountMapping(mapping: schema, signature: signature)
    }
}
