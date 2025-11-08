import Foundation

public enum TUIFeatureFlags {
    public static var isReconcilerEnabled: Bool {
        return ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_RECONCILER"] == "1"
    }

    public static var isBufferEnabled: Bool {
        return ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_BUFFER"] == "1"
    }

    public static var isStatusPanelDeclarative: Bool {
        let env = ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_STATUS_DECLARATIVE"]
        return env != "0"
    }

    public static var isBalancesPanelDeclarative: Bool {
        let env = ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_BALANCES_DECLARATIVE"]
        return env != "0"
    }

    public static var isActivityPanelDeclarative: Bool {
        let env = ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE"]
        return env != "0"
    }

    public static var isPricePanelDeclarative: Bool {
        let env = ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_PRICE_DECLARATIVE"]
        return env != "0"
    }

    // New structural upgrade flags
    public static var isDirtyGraphEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_DIRTY_GRAPH"] == "1"
    }

    public static var isWidthCacheEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_WIDTH_CACHE"] != "0" // Default enabled
    }

    public static var isDamageRectsEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_DAMAGE_RECTS"] == "1"
    }

    public static var isTailEditEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_TAIL_EDIT"] != "0" // Default enabled
    }

    public static var bytesCap: Int {
        if let capStr = ProcessInfo.processInfo.environment["TUI_BYTES_CAP"],
           let cap = Int(capStr) {
            return cap
        }
        return 6144 // Default 6 KiB
    }

    public static var isDebugMetricsEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_DEBUG_METRICS"] == "1"
    }

    public static var isDebugOverlayEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_DEBUG_OVERLAY"] == "1"
    }

    public static var isDebugTreeEnabled: Bool {
        ProcessInfo.processInfo.environment["TUI_DEBUG_TREE"] == "1"
    }

    public static func checkAndAssert(flag: String, condition: Bool, message: String) {
        if !condition {
            assertionFailure("TUI Feature Flag \(flag): \(message)")
        }
    }
}
