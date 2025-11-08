import Foundation
import Utils

#if os(macOS) || os(Linux)
import Darwin
#endif

public enum KeyEvent: Sendable, Equatable {
    case character(Character)
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case enter
    case backspace
    case escape
    case tab
    case control(Character)
    case unknown([UInt8])

    public static func == (lhs: KeyEvent, rhs: KeyEvent) -> Bool {
        switch (lhs, rhs) {
        case (.character(let l), .character(let r)):
            return l == r
        case (.arrowUp, .arrowUp),
             (.arrowDown, .arrowDown),
             (.arrowLeft, .arrowLeft),
             (.arrowRight, .arrowRight),
             (.enter, .enter),
             (.backspace, .backspace),
             (.escape, .escape),
             (.tab, .tab):
            return true
        case (.control(let l), .control(let r)):
            return l == r
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}

public final class KeyboardHandler: @unchecked Sendable {
    private let terminalSecurity: TerminalSecurity
    private let logger: StructuredLogger
    private let inputProcessor: InputProcessor
    private var isActive = false
    private var readTask: Task<Void, Never>?
    private nonisolated(unsafe) var originalFileDescriptorFlags: Int32?

    public init(logger: StructuredLogger = StructuredLogger(), terminalSecurity: TerminalSecurity? = nil) {
        self.logger = logger
        self.terminalSecurity = terminalSecurity ?? TerminalSecurity(logger: logger)
        self.inputProcessor = InputProcessor()
    }

    public func startReading() throws -> AsyncStream<KeyEvent> {
        guard !isActive else {
            throw KeyboardHandlerError.alreadyActive
        }

        let stdinHandle = FileHandle.standardInput
        let fd = stdinHandle.fileDescriptor

        #if os(macOS) || os(Linux)
        if isatty(fd) == 0 {
            logger.warn(component: "KeyboardHandler", event: "stdin is not a TTY, keyboard input may not work")
        }
        #endif

        _ = try terminalSecurity.setupTerminal()
        isActive = true

        return AsyncStream { continuation in
            readTask = Task {
                await readInput(continuation: continuation)
            }

            continuation.onTermination = { @Sendable _ in
                self.stop()
            }
        }
    }

    public func stop() {
        guard isActive else { return }

        isActive = false
        inputProcessor.stop()
        readTask?.cancel()
        readTask = nil

        #if os(macOS) || os(Linux)
        let fd = FileHandle.standardInput.fileDescriptor
        restoreFileDescriptorFlags(fd: fd)
        #endif

        terminalSecurity.restoreTerminalState()

        logger.debug(component: "KeyboardHandler", event: "Stopped reading keyboard input")
    }

    deinit {
        stop()
    }

    private func readInput(continuation: AsyncStream<KeyEvent>.Continuation) async {
        let stdinHandle = FileHandle.standardInput
        let fd = stdinHandle.fileDescriptor

        logger.debug(component: "KeyboardHandler", event: "Started reading keyboard input")

        #if os(macOS) || os(Linux)
        let originalFlags = fcntl(fd, F_GETFL)
        originalFileDescriptorFlags = originalFlags

        _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)

        defer {
            restoreFileDescriptorFlags(fd: fd)
        }
        #endif

        await inputProcessor.startProcessing(fd: fd, continuation: continuation)

        logger.debug(component: "KeyboardHandler", event: "Finished reading keyboard input")
    }

    private nonisolated func restoreFileDescriptorFlags(fd: Int32) {
        #if os(macOS) || os(Linux)
        if let originalFlags = originalFileDescriptorFlags {
            _ = fcntl(fd, F_SETFL, originalFlags)
            originalFileDescriptorFlags = nil
        }
        #endif
    }

}

public enum KeyboardHandlerError: Error {
    case alreadyActive
    case failedToSetupTerminal
}
