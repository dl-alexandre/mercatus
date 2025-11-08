import Foundation
import CryptoKit

public actor KeyRotationManager {
    private var currentKeys: [String: SymmetricKey] = [:]
    private var rotationSchedule: [String: Date] = [:]
    private let rotationInterval: TimeInterval

    public init(rotationInterval: TimeInterval = 7 * 24 * 60 * 60) {
        self.rotationInterval = rotationInterval
    }

    public func registerKey(_ keyName: String, key: SymmetricKey) {
        currentKeys[keyName] = key
        rotationSchedule[keyName] = Date().addingTimeInterval(rotationInterval)
    }

    public func shouldRotate(_ keyName: String) -> Bool {
        guard let nextRotation = rotationSchedule[keyName] else {
            return false
        }
        return Date() >= nextRotation
    }

    public func rotateKey(_ keyName: String, newKey: SymmetricKey) {
        currentKeys[keyName] = newKey
        rotationSchedule[keyName] = Date().addingTimeInterval(rotationInterval)
    }

    public func getKey(_ keyName: String) -> SymmetricKey? {
        return currentKeys[keyName]
    }

    public func loadKeyFromEnvironment(_ keyName: String) -> SymmetricKey? {
        guard let keyString = ProcessInfo.processInfo.environment[keyName] else {
            return nil
        }
        let keyData = Data(keyString.utf8)
        return SymmetricKey(data: keyData)
    }
}
