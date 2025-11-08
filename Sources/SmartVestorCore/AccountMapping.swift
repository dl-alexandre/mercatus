import Foundation
import CryptoKit

public struct AccountMapping {
    private static let nameSpace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!

    public static func accountID(exchange: String, asset: String, userId: String? = nil) -> UUID {
        var combined: String
        if let userId = userId, !userId.isEmpty {
            combined = "\(userId):\(exchange):\(asset)".lowercased()
        } else {
            combined = "\(exchange):\(asset)".lowercased()
        }
        return UUID.name(combined, nameSpace: nameSpace)
    }

    public static func feeAccountID(exchange: String) -> UUID {
        return accountID(exchange: exchange, asset: "FEE")
    }

    public static func decodeAccountID(_ accountID: UUID) -> (exchange: String, asset: String)? {
        return nil
    }

    public static func encodeAccountID(exchange: String, asset: String) -> Data {
        let accountID = self.accountID(exchange: exchange, asset: asset)
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: accountID.uuid) { buffer in
            uuidBytes = Array(buffer)
        }
        return Data(uuidBytes)
    }
}

extension UUID {
    static func name(_ name: String, nameSpace: UUID) -> UUID {
        let nameData = name.data(using: .utf8)!
        var namespaceBytes = [UInt8](repeating: 0, count: 16)

        withUnsafeBytes(of: nameSpace.uuid) { namespaceBuffer in
            namespaceBytes = Array(namespaceBuffer)
        }

        var combined = Data()
        combined.append(contentsOf: namespaceBytes)
        combined.append(nameData)

        let hash = SHA512.hash(data: combined)
        var hashBytes = Array(hash.prefix(16))

        hashBytes[6] = (hashBytes[6] & 0x0F) | 0x50
        hashBytes[8] = (hashBytes[8] & 0x3F) | 0x80

        var uuid = uuid_t(
            hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
            hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
            hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
            hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
        )
        return UUID(uuid: uuid)
    }
}
