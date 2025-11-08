#if os(macOS) || os(Linux)
import Darwin
import Foundation

private let _ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()

public actor RenderBus {
    private let fd: Int32 = STDOUT_FILENO
    private var fallbackFileHandle: FileHandle?
    private var fallbackFilePath: String?
    private var lastTTYCheck: (time: Date, isTTY: Bool)?
    private var terminalResumed = false
    private let ttyCheckInterval: TimeInterval = 0.5
    private static let sighupHandlerLock = NSLock()
    private nonisolated(unsafe) static var sighupHandlerInstalled = false

    public init() {
        _ = _ignoreSigpipe
        setupSighupHandler()
        makeBlocking()
        Task {
            await setupFallbackLogging()
            await startTTYMonitoring()
        }
    }

    private nonisolated func setupSighupHandler() {
        RenderBus.sighupHandlerLock.lock()
        defer { RenderBus.sighupHandlerLock.unlock() }

        guard !RenderBus.sighupHandlerInstalled else { return }
        RenderBus.sighupHandlerInstalled = true

        signal(SIGHUP) { _ in
            Task {
                await Runtime.renderBus.reinitialize()
            }
        }
    }

    private func setupFallbackLogging() async {
        let logPath = ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"] ?? "/tmp/smartvestor-tui.log"
        fallbackFilePath = logPath

        let url = URL(fileURLWithPath: logPath)
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: logPath) {
            fileManager.createFile(atPath: logPath, contents: nil)
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            if #available(macOS 10.15, *) {
                _ = try? handle.seekToEnd()
            } else {
                handle.seekToEndOfFile()
            }
            fallbackFileHandle = handle
        }
    }

    private func startTTYMonitoring() async {
        Task {
            var lastTTYState = isOutputTTY()
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let currentTTYState = isOutputTTY()
                if !lastTTYState && currentTTYState {
                    terminalResumed = true
                    reinitialize()
                }
                lastTTYState = currentTTYState
            }
        }
    }

    public func reinitialize() {
        terminalResumed = true
        if let handle = fallbackFileHandle {
            if #available(macOS 10.15.4, *) {
                try? handle.close()
            } else {
                handle.closeFile()
            }
        }
        fallbackFileHandle = nil
        lastTTYCheck = nil
        Task {
            await setupFallbackLogging()
        }
    }

    public func isOutputTTY() -> Bool {
        let now = Date()
        if let last = lastTTYCheck, now.timeIntervalSince(last.time) < ttyCheckInterval {
            return last.isTTY
        }
        let result = isatty(STDOUT_FILENO) != 0
        lastTTYCheck = (now, result)
        return result
    }

    public func hasTerminalResumed() -> Bool {
        let result = terminalResumed
        terminalResumed = false
        return result
    }

    public func write(_ s: String) {
        guard isOutputTTY() else {
            writeToFallback(s)
            return
        }

        let bytes = Array(s.utf8)
        #if DEBUG
        if let debugEnv = getenv("RENDER_DEBUG"), String(cString: debugEnv) == "1" {
            let debugMsg = "[RenderBus] writing \(bytes.count) bytes\n"
            _ = debugMsg.withCString { Darwin.write(STDERR_FILENO, $0, debugMsg.utf8.count) }
        }
        #endif

        var off = 0
        while off < bytes.count {
            let wrote = bytes.withUnsafeBytes { ptr -> Int in
                let base = ptr.baseAddress!.advanced(by: off)
                return Darwin.write(fd, base, bytes.count - off)
            }
            #if DEBUG
            if let debugEnv = getenv("RENDER_DEBUG"), String(cString: debugEnv) == "1" {
                let debugMsg = "[RenderBus] wrote \(wrote) bytes (total: \(bytes.count), offset: \(off))\n"
                _ = debugMsg.withCString { Darwin.write(STDERR_FILENO, $0, debugMsg.utf8.count) }
            }
            #endif
            if wrote > 0 { off += wrote; continue }
            if wrote == -1 {
                let errorCode = errno
                #if DEBUG
                if let debugEnv = getenv("RENDER_DEBUG"), String(cString: debugEnv) == "1" {
                    let debugMsg = "[RenderBus] write error: \(errorCode) (EPIPE=\(EPIPE))\n"
                    _ = debugMsg.withCString { Darwin.write(STDERR_FILENO, $0, debugMsg.utf8.count) }
                }
                #endif
                switch errorCode {
                case EINTR: continue
                case EAGAIN: usleep(1000); continue
                case EPIPE:
                    writeToFallback(s)
                    return
                default:
                    writeToFallback(s)
                    return
                }
            }
        }
    }

    private func writeToFallback(_ s: String) {
        let cleaned = stripANSI(s)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(cleaned)\n"

        guard let handle = fallbackFileHandle else {
            if let path = fallbackFilePath, logLine.data(using: .utf8) != nil {
                let url = URL(fileURLWithPath: path)
                if let handle = try? FileHandle(forWritingTo: url) {
                    if #available(macOS 10.15, *) {
                        _ = try? handle.seekToEnd()
                    } else {
                        handle.seekToEndOfFile()
                    }
                    fallbackFileHandle = handle
                    if let data = logLine.data(using: .utf8) {
                        try? handle.write(contentsOf: data)
                        if #available(macOS 10.15.4, *) {
                            try? handle.synchronize()
                        } else {
                            handle.synchronizeFile()
                        }
                    }
                }
            }
            return
        }

        guard let data = logLine.data(using: .utf8) else { return }

        do {
            try handle.write(contentsOf: data)
            if #available(macOS 10.15.4, *) {
                try handle.synchronize()
            } else {
                handle.synchronizeFile()
            }
        } catch {
            fallbackFileHandle = nil
        }
    }

    private func stripANSI(_ text: String) -> String {
        let pattern = #"\x1B\[[0-9;]*[A-Za-z]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private nonisolated func makeBlocking() {
        let flags = fcntl(STDOUT_FILENO, F_GETFL)
        if flags & O_NONBLOCK != 0 { _ = fcntl(STDOUT_FILENO, F_SETFL, flags & ~O_NONBLOCK) }
    }

    deinit {
        if let handle = fallbackFileHandle {
            if #available(macOS 10.15.4, *) {
                try? handle.close()
            } else {
                handle.closeFile()
            }
        }
    }
}

public enum Runtime {
    public static let renderBus = RenderBus()
}

#else
import Foundation

public actor RenderBus {
    private let fd: Int32 = STDOUT_FILENO

    public init() {}

    public func write(_ s: String) {
        print(s, terminator: "")
        fflush(stdout)
    }

    private func makeBlocking() {}
}

public enum Runtime {
    public static let renderBus = RenderBus()
}
#endif
