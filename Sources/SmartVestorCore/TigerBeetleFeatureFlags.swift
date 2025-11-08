import Foundation

public enum CutoverFeatureFlag {
    case readFromTigerBeetle
    case disableSQLiteWrites
    case mirrorWrites
}

public actor FeatureFlagManager {
    private var flags: Set<CutoverFeatureFlag> = [.mirrorWrites]

    public init(initialFlags: Set<CutoverFeatureFlag> = [.mirrorWrites]) {
        self.flags = initialFlags
    }

    public func isEnabled(_ flag: CutoverFeatureFlag) -> Bool {
        return flags.contains(flag)
    }

    public func enable(_ flag: CutoverFeatureFlag) {
        flags.insert(flag)
    }

    public func disable(_ flag: CutoverFeatureFlag) {
        flags.remove(flag)
    }

    public func getAllFlags() -> Set<CutoverFeatureFlag> {
        return flags
    }
}
