import Foundation
import Utils
import CryptoKit

public class SecretsRotationTester {
    private let keyRotationManager: KeyRotationManager
    private let logger: StructuredLogger

    public init(keyRotationManager: KeyRotationManager, logger: StructuredLogger = StructuredLogger()) {
        self.keyRotationManager = keyRotationManager
        self.logger = logger
    }

    public func testZeroDowntimeRotation() async throws -> Bool {
        logger.info(component: "SecretsRotation", event: "Testing zero-downtime rotation")

        let keyName = "TIGERBEETLE_SIGNING_SECRET"
        let key1 = await keyRotationManager.getKey(keyName)
        let key2 = await keyRotationManager.loadKeyFromEnvironment(keyName)
        let originalKey = key1 ?? key2
        guard originalKey != nil else {
            throw SmartVestorError.persistenceError("Could not load original signing key")
        }

        let newSecretKey = SymmetricKey(size: .bits256)
        let newSecretData = newSecretKey.withUnsafeBytes { Data($0) }

        setenv("TIGERBEETLE_SIGNING_SECRET", newSecretData.base64EncodedString(), 1)

        let key3 = await keyRotationManager.getKey(keyName)
        let key4 = await keyRotationManager.loadKeyFromEnvironment(keyName)
        let rotatedKey = key3 ?? key4
        guard let finalKey = rotatedKey else {
            throw SmartVestorError.persistenceError("Could not load rotated signing key")
        }

        let config = TigerBeetleConfig(enabled: true)
        let sealer = TigerBeetleConfigSealer(secretKey: finalKey)

        do {
            let sealed = try sealer.seal(config)
            let isValid = sealer.verify(sealed)

            if !isValid {
                logger.error(component: "SecretsRotation", event: "Rotation test failed: signature verification failed")
                return false
            }
        } catch {
            logger.error(component: "SecretsRotation", event: "Rotation test failed", data: ["error": error.localizedDescription])
            return false
        }

        logger.info(component: "SecretsRotation", event: "Zero-downtime rotation test passed")
        return true
    }
}
