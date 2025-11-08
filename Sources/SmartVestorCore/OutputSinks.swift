import Foundation

public final class CapturingStream: TextOutputStream {
    public private(set) var buffer = ""

    public func write(_ string: String) {
        buffer += string
    }

    public func clear() {
        buffer = ""
    }
}

public struct StdoutStream: TextOutputStream {
    public func write(_ string: String) {
        fputs(string, stdout)
    }
}
