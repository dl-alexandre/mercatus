import Foundation
import CryptoKit

public struct SealedConfig {
    public let config: TigerBeetleConfig
    public let signature: String
    public let timestamp: Date

    public init(config: TigerBeetleConfig, signature: String, timestamp: Date = Date()) {
        self.config = config
        self.signature = signature
        self.timestamp = timestamp
    }

    public func verify(secretKey: SymmetricKey) -> Bool {
        let data = try! JSONEncoder().encode(config)
        let signatureData = Data(hexString: signature) ?? Data()

        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: secretKey)
        return Data(hmac) == signatureData
    }
}

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex

        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }

        self = data
    }

    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

public class TigerBeetleConfigSealer {
    private let secretKey: SymmetricKey

    public init(secretKey: SymmetricKey) {
        self.secretKey = secretKey
    }

    public init(secretKeyString: String) {
        let keyData = Data(secretKeyString.utf8)
        self.secretKey = SymmetricKey(data: keyData)
    }

    public func seal(_ config: TigerBeetleConfig) throws -> SealedConfig {
        let data = try JSONEncoder().encode(config)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: secretKey)
        let signature = Data(hmac).hexString

        return SealedConfig(config: config, signature: signature)
    }

    public func verify(_ sealed: SealedConfig) -> Bool {
        return sealed.verify(secretKey: secretKey)
    }
}

public class TigerBeetleConfigLoader {
    public static func loadWithVerification(
        sealedConfig: SealedConfig?,
        secretKey: SymmetricKey?,
        production: Bool
    ) throws -> TigerBeetleConfig {
        if let sealed = sealedConfig, let key = secretKey {
            guard sealed.verify(secretKey: key) else {
                throw SmartVestorError.configurationError("Config signature verification failed")
            }
            return sealed.config
        }

        if production {
            throw SmartVestorError.configurationError("Production mode requires sealed config")
        }

        return TigerBeetleConfig()
    }
}
