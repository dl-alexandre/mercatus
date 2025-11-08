import Foundation
import Utils

#if os(macOS) || os(Linux)
import Darwin
import Dispatch
#elseif os(Windows)
import WinSDK
#endif

public final class TerminalSecurity: @unchecked Sendable {
    private var originalTermios: termios?
    private var originalAttributes: [FileHandle: termios] = [:]
    private let logger: StructuredLogger
    private var isInitialized = false
    private static nonisolated(unsafe) var terminalOpsRef: RealTerminalOperations?
    private var signalHandlers: [DispatchSourceSignal] = []
    private var installed = false
    public private(set) var isReady = false
    private let term: RealTerminalOperations
    #if os(macOS) || os(Linux)
    private static nonisolated(unsafe) var quitFlagRef: (any QuitFlagProtocol)?
    private static nonisolated(unsafe) var quitFlagLock = os_unfair_lock()
    #endif
    private static nonisolated(unsafe) var instanceLock = os_unfair_lock()
    private static nonisolated(unsafe) var _currentInstance: TerminalSecurity?
    private static var currentInstance: TerminalSecurity? {
        get {
            os_unfair_lock_lock(&instanceLock)
            defer { os_unfair_lock_unlock(&instanceLock) }
            return _currentInstance
        }
        set {
            os_unfair_lock_lock(&instanceLock)
            defer { os_unfair_lock_unlock(&instanceLock) }
            _currentInstance = newValue
        }
    }

    #if os(macOS) || os(Linux)
    fileprivate static nonisolated(unsafe) var sigwinchLock = os_unfair_lock()
    fileprivate static nonisolated(unsafe) var lastResizeTime: timeval = timeval(tv_sec: 0, tv_usec: 0)
    fileprivate static let resizeDebounceMs: Int64 = 100
    private static nonisolated(unsafe) var didRegisterAtExit = false
    private static nonisolated(unsafe) var atExitLock = os_unfair_lock()
    #endif

    public protocol QuitFlagProtocol: Sendable {
        func set() async
    }

    public init(logger: StructuredLogger = StructuredLogger(), term: RealTerminalOperations? = nil) {
        self.logger = logger
        self.term = term ?? RealTerminalOperations()
    }

    deinit {
        restoreTerminalState()
        if TerminalSecurity.currentInstance === self {
            TerminalSecurity.currentInstance = nil
        }
    }

    public func setQuitFlag(_ flag: (any QuitFlagProtocol)?) {
        #if os(macOS) || os(Linux)
        os_unfair_lock_lock(&Self.quitFlagLock)
        defer { os_unfair_lock_unlock(&Self.quitFlagLock) }
        Self.quitFlagRef = flag
        #endif
    }

    @discardableResult
    public func setupTerminal() throws -> Bool {
        #if TESTING
        isInitialized = true
        isReady = true
        return true
        #else
        if isInitialized {
            return isReady
        }

        #if os(macOS) || os(Linux)
        signal(SIGPIPE, SIG_IGN)

        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            fputs("Non-TTY detected. Disabling TUI.\n", stderr)
            isReady = false
            isInitialized = true
            installed = true
            throw TerminalSecurityError.nonTTY
        }

        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput
        let stderrHandle = FileHandle.standardError

        guard stdinHandle.fileDescriptor >= 0,
              stdoutHandle.fileDescriptor >= 0,
              stderrHandle.fileDescriptor >= 0 else {
            throw TerminalSecurityError.invalidFileDescriptor
        }

        var term: termios = termios()
        guard tcgetattr(stdinHandle.fileDescriptor, &term) == 0 else {
            throw TerminalSecurityError.failedToGetTerminalAttributes
        }

        originalTermios = term
        originalAttributes[stdinHandle] = term
        originalAttributes[stdoutHandle] = term
        originalAttributes[stderrHandle] = term

        var newTerm = term
        cfmakeraw(&newTerm)
        newTerm.c_iflag |= UInt(ICRNL)
        newTerm.c_oflag |= UInt(OPOST)

        guard tcsetattr(stdinHandle.fileDescriptor, TCSANOW, &newTerm) == 0 else {
            throw TerminalSecurityError.failedToSetTerminalAttributes
        }

        hideCursor()
        installAtExitOnce()
        #endif

        TerminalSecurity.terminalOpsRef = self.term

        TerminalSecurity.currentInstance = self
        installOnce()
        isInitialized = true
        isReady = true

        logger.debug(component: "TerminalSecurity", event: "Terminal setup completed", data: [
            "stdin_fd": String(stdinHandle.fileDescriptor),
            "stdout_fd": String(stdoutHandle.fileDescriptor),
            "stderr_fd": String(stderrHandle.fileDescriptor)
        ])

        return true
        #endif
    }

    private func hideCursor() {
        #if os(macOS) || os(Linux)
        FileHandle.standardOutput.write(Data("\u{1B}[?25l".utf8))
        #endif
    }

    private func showCursor() {
        #if os(macOS) || os(Linux)
        FileHandle.standardOutput.write(Data("\u{1B}[?25h".utf8))
        #endif
    }

    private func installAtExitOnce() {
        #if os(macOS) || os(Linux)
        os_unfair_lock_lock(&TerminalSecurity.atExitLock)
        defer { os_unfair_lock_unlock(&TerminalSecurity.atExitLock) }

        guard !TerminalSecurity.didRegisterAtExit else { return }
        TerminalSecurity.didRegisterAtExit = true
        atexit {
            TerminalSecurity.currentInstance?.restoreTerminal()
        }
        #endif
    }

    public func restoreTerminal() {
        #if os(macOS) || os(Linux)
        showCursor()
        #endif
        restoreTerminalState()
    }

    public func restoreTerminalState() {
        #if TESTING
        isInitialized = false
        isReady = false
        if TerminalSecurity.currentInstance === self {
            TerminalSecurity.currentInstance = nil
        }
        return
        #else
        guard isInitialized else { return }

        term.exitAltScreen()

        #if os(macOS) || os(Linux)
        showCursor()
        os_unfair_lock_lock(&Self.instanceLock)
        defer { os_unfair_lock_unlock(&Self.instanceLock) }

        guard let original = originalTermios else {
            logger.warn(component: "TerminalSecurity", event: "No original terminal state to restore")
            isInitialized = false
            isReady = false
            if TerminalSecurity.currentInstance === self {
                TerminalSecurity.currentInstance = nil
            }
            return
        }

        let stdinHandle = FileHandle.standardInput
        var term = original

        if tcsetattr(stdinHandle.fileDescriptor, TCSANOW, &term) == 0 {
            logger.debug(component: "TerminalSecurity", event: "Terminal state restored")
        } else {
            logger.error(component: "TerminalSecurity", event: "Failed to restore terminal state", data: ["error": "failedToRestoreTerminalAttributes"])
        }
        #endif

        isInitialized = false
        isReady = false
        originalTermios = nil
        originalAttributes.removeAll()

        if TerminalSecurity.currentInstance === self {
            TerminalSecurity.currentInstance = nil
        }
        #endif
    }

    public func sanitizeInput(_ input: String) -> String {
        let ansiEscapePattern = #"\x1B\[[\d;]*[a-zA-Z]"#
        let sanitized = input.replacingOccurrences(
            of: ansiEscapePattern,
            with: "",
            options: [.regularExpression]
        )

        let controlChars = CharacterSet.controlCharacters
        let filtered = sanitized.unicodeScalars.filter { scalar in
            guard let char = UnicodeScalar(scalar.value) else { return false }
            if controlChars.contains(char) {
                switch char.value {
                case 9, 10, 13:
                    return true
                default:
                    return false
                }
            }
            return true
        }

        let result = String(String.UnicodeScalarView(filtered))

        if result != input {
            logger.debug(component: "TerminalSecurity", event: "Input sanitized", data: [
                "original_length": String(input.count),
                "sanitized_length": String(result.count)
            ])
        }

        return result
    }

    public func sanitizeServerString(_ string: String) -> String {
        var sanitized = sanitizeInput(string)

        sanitized = sanitized.replacingOccurrences(of: "\u{001B}", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\u{009B}", with: "")

        let allowedControlChars: Set<UInt32> = [9, 10, 13, 32]
        let filtered = sanitized.unicodeScalars.filter { scalar in
            if scalar.value < 32 && !allowedControlChars.contains(scalar.value) {
                return false
            }
            if scalar.value == 127 {
                return false
            }
            if scalar.value >= 0x80 && scalar.value < 0xA0 {
                return false
            }
            return true
        }

        return String(String.UnicodeScalarView(filtered))
    }

    public func cleanupFileDescriptors() {
        let handles: [FileHandle] = [
            FileHandle.standardInput,
            FileHandle.standardOutput,
            FileHandle.standardError
        ]

        for handle in handles {
            let fd = handle.fileDescriptor
            guard fd >= 0 else { continue }

            if fcntl(fd, F_GETFD) == -1 {
                if errno != EBADF {
                    logger.warn(component: "TerminalSecurity", event: "File descriptor check failed", data: [
                        "fd": String(fd),
                        "errno": String(errno)
                    ])
                }
            }
        }

        logger.debug(component: "TerminalSecurity", event: "File descriptors checked and validated")
    }

    public func installOnce() {
        #if TESTING
        return
        #else
        guard !installed else { return }
        installed = true

        #if os(macOS) || os(Linux)
        guard isatty(STDOUT_FILENO) != 0 else {
            logger.warning(component: "TerminalSecurity", event: "Non-TTY stdout detected, skipping full-screen mode")
            return
        }

        signal(SIGPIPE, SIG_IGN)

        for s in [SIGINT, SIGTERM, SIGQUIT, SIGHUP, SIGWINCH] {
            signal(s, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
            src.setEventHandler { [term] in
                if s == SIGWINCH {
                    term.publishResizeEvent()
                    handleSigwinchSignal()
                    return
                }
                term.exitAltScreen()
                fflush(stdout)
                _Exit(Int32(128) &+ s)
            }
            src.resume()
            signalHandlers.append(src)
        }

        term.enterAltScreen()

        TerminalSecurity.terminalOpsRef = term
        atexit {
            TerminalSecurity.terminalOpsRef?.exitAltScreen()
        }
        #endif
        #endif
    }

    private func setupSignalHandlers() {
        #if os(macOS) || os(Linux)
        installOnce()
        #endif
    }

    private func restoreTerminalStateSync() {
        #if TESTING
        isInitialized = false
        if TerminalSecurity.currentInstance === self {
            TerminalSecurity.currentInstance = nil
        }
        return
        #else
        guard isInitialized else { return }

        term.exitAltScreen()

        #if os(macOS) || os(Linux)
        os_unfair_lock_lock(&Self.instanceLock)
        defer { os_unfair_lock_unlock(&Self.instanceLock) }

        guard let original = originalTermios else {
            isInitialized = false
            if TerminalSecurity.currentInstance === self {
                TerminalSecurity.currentInstance = nil
            }
            return
        }

        let stdinHandle = FileHandle.standardInput
        var term = original
        _ = tcsetattr(stdinHandle.fileDescriptor, TCSANOW, &term)
        #endif

        isInitialized = false
        originalTermios = nil
        originalAttributes.removeAll()

        if TerminalSecurity.currentInstance === self {
            TerminalSecurity.currentInstance = nil
        }
        #endif
    }
}

#if os(macOS) || os(Linux)
private func handleSigwinchSignal() {
    os_unfair_lock_lock(&TerminalSecurity.sigwinchLock)
    defer { os_unfair_lock_unlock(&TerminalSecurity.sigwinchLock) }

    var now = timeval()
    gettimeofday(&now, nil)
    let lastTime = TerminalSecurity.lastResizeTime
    let elapsedSec = Int64(now.tv_sec) - Int64(lastTime.tv_sec)
    let elapsedUsec = Int64(now.tv_usec) - Int64(lastTime.tv_usec)
    let elapsedMs = elapsedSec * 1000 + elapsedUsec / 1000

    guard elapsedMs >= TerminalSecurity.resizeDebounceMs else {
        return
    }

    TerminalSecurity.lastResizeTime = now

    var winsize = winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
    let TIOCGWINSZ: UInt = 0x40087468
    _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize)
}
#endif

public enum TerminalSecurityError: Error {
    case invalidFileDescriptor
    case failedToGetTerminalAttributes
    case failedToSetTerminalAttributes
    case failedToRestoreTerminalAttributes
    case nonTTY
}

#if os(macOS) || os(Linux)
private func cfmakeraw(_ term: UnsafeMutablePointer<termios>) {
    term.pointee.c_iflag &= ~(UInt(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON))
    term.pointee.c_oflag &= ~UInt(OPOST)
    term.pointee.c_lflag &= ~(UInt(ECHO | ECHONL | ICANON | ISIG | IEXTEN))
    term.pointee.c_cflag &= ~(UInt(CSIZE | PARENB))
    term.pointee.c_cflag |= UInt(CS8)
    term.pointee.c_cc.16 = 0
    term.pointee.c_cc.17 = 1
}
#endif
