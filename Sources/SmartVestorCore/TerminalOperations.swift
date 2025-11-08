import Foundation

#if os(macOS) || os(Linux)
import Darwin
#endif

enum ANSI {
    static let esc = "\u{001B}["
    static let enterAlt = esc + "?1049h"
    static let exitAlt  = esc + "?1049l"
    static let clearAll = esc + "H" + esc + "2J"
    static let hideCur  = esc + "?25l"
    static let showCur  = esc + "?25h"
    static let pasteOn  = esc + "?2004h"
    static let pasteOff = esc + "?2004l"
    static let mouseOn  = esc + "?1002h" + esc + "?1006h"
    static let mouseOff = esc + "?1006l" + esc + "?1002l"
}

public struct TerminalSize: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = max(80, cols)
        self.rows = max(24, rows)
    }

    public static let minimum = TerminalSize(cols: 80, rows: 24)

    public init(width: Int, height: Int) {
        self.cols = max(80, width)
        self.rows = max(24, height)
    }

    public var width: Int { cols }
    public var height: Int { rows }

    public var isValid: Bool {
        return cols >= 80 && rows >= 24
    }
}

public protocol TerminalOperations: Sendable {
    var size: TerminalSize { get }
    func clearScreen()
    func setCursor(row: Int, col: Int)
    func enableRawMode()
    func disableRawMode()
    func writeANSI(_ code: String)
    func enterAltScreen()
    func exitAltScreen()
}

public final class MockTerminalOperations: TerminalOperations, @unchecked Sendable {
    private let sizeLock = NSLock()
    private var _size: TerminalSize

    public var size: TerminalSize {
        get {
            sizeLock.lock()
            defer { sizeLock.unlock() }
            return _size
        }
        set {
            sizeLock.lock()
            defer { sizeLock.unlock() }
            _size = newValue
        }
    }

    public init(size: TerminalSize = .init(cols: 80, rows: 24)) {
        self._size = size
    }

    public func clearScreen() {}

    public func setCursor(row: Int, col: Int) {}

    public func enableRawMode() {}

    public func disableRawMode() {}

    public func writeANSI(_ code: String) {}

    public func enterAltScreen() {}

    public func exitAltScreen() {}
}

public final class RealTerminalOperations: TerminalOperations {
    public var size: TerminalSize {
        #if os(macOS) || os(Linux)
        var winsize = winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
        let TIOCGWINSZ: UInt = 0x40087468
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize)
        if result == 0 {
            let cols = Int(winsize.ws_col)
            let rows = Int(winsize.ws_row)
            if cols > 0 && rows > 0 {
                return TerminalSize(cols: cols, rows: rows)
            }
        }
        #endif

        if let columns = ProcessInfo.processInfo.environment["COLUMNS"],
           let rows = ProcessInfo.processInfo.environment["LINES"],
           let cols = Int(columns),
           let rowsInt = Int(rows),
           cols > 0 && rowsInt > 0 {
            return TerminalSize(cols: cols, rows: rowsInt)
        }

        return TerminalSize.minimum
    }

    public init() {}

    public func clearScreen() {
        write(ANSI.clearAll)
    }

    public func setCursor(row: Int, col: Int) {
        write("\(ANSI.esc)\(row);\(col)H")
    }

    public func enableRawMode() {
        #if !TESTING && (os(macOS) || os(Linux))
        let stdinHandle = FileHandle.standardInput
        var term: termios = termios()
        guard tcgetattr(stdinHandle.fileDescriptor, &term) == 0 else { return }

        var newTerm = term
        cfmakeraw(&newTerm)
        newTerm.c_iflag |= UInt(ICRNL)
        newTerm.c_oflag |= UInt(OPOST)

        _ = tcsetattr(stdinHandle.fileDescriptor, TCSANOW, &newTerm)
        #endif
    }

    public func disableRawMode() {
        #if !TESTING && (os(macOS) || os(Linux))
        let stdinHandle = FileHandle.standardInput
        var term: termios = termios()
        guard tcgetattr(stdinHandle.fileDescriptor, &term) == 0 else { return }
        _ = tcsetattr(stdinHandle.fileDescriptor, TCSANOW, &term)
        #endif
    }

    public func writeANSI(_ code: String) {
        write(code)
    }

    public func enterAltScreen() {
        write(ANSI.enterAlt + ANSI.clearAll + ANSI.hideCur + ANSI.pasteOn)
    }

    public func exitAltScreen() {
        write(ANSI.mouseOff + ANSI.pasteOff + ANSI.showCur + ANSI.exitAlt)
    }

    public func publishResizeEvent() {
        NotificationCenter.default.post(name: NSNotification.Name("TerminalResize"), object: nil)
    }

    private func write(_ s: String) {
        Task {
            await Runtime.renderBus.write(s)
        }
    }
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
