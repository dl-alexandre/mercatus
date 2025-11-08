import Foundation
import Synchronization
#if os(macOS) || os(Linux)
import Darwin
#endif

private struct GuardState {
    var activeTokens: Set<UInt64> = []
    var tokenCounter: UInt64 = 1
}

public final class TUIWriteGuard: @unchecked Sendable {
    private static let state = Mutex(GuardState())

    public static func createToken() -> UInt64 {
        state.withLock { state in
            let token = state.tokenCounter
            state.tokenCounter &+= 1
            state.activeTokens.insert(token)
            return token
        }
    }

    public static func releaseToken(_ token: UInt64) {
        _ = state.withLock { state in
            state.activeTokens.remove(token)
        }
    }

    public static func assertWriteAllowed(token: UInt64? = nil, file: StaticString = #file, line: UInt = #line) {
        if ProcessInfo.processInfo.environment["TUI_WRITE_GUARD_DISABLE"] == "1" {
            return
        }

        state.withLock { state in
            if state.activeTokens.isEmpty {
                return
            }

            if let token = token {
                guard state.activeTokens.contains(token) else {
                    fatalError("TUI Write Guard: Invalid or released token \(token) from \(file):\(line)")
                }
            } else {
                guard state.activeTokens.count == 1, let _ = state.activeTokens.first else {
                    return
                }
            }
        }
    }
}
