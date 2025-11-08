import Foundation
import os.log

#if os(macOS) || os(Linux)
import Darwin
import Foundation
#endif

public final class InputProcessor: @unchecked Sendable {
    /// Maximum input sequence length in bytes.
    /// Rationale: ANSI escape sequences are typically at most ~32 bytes.
    /// Using 64 bytes provides a 2x safety margin while preventing DoS attacks.
    private static let MAX_INPUT_SEQUENCE_LENGTH = 64

    private var buffer = Data()
    private var timeoutTimer: DispatchSourceTimer?
    private let timeoutInterval: TimeInterval = 0.1
    private let logger: os.Logger
    private nonisolated(unsafe) var isActive = false
    private nonisolated(unsafe) var continuation: AsyncStream<KeyEvent>.Continuation?

    public init(logger: os.Logger = os.Logger(subsystem: "com.smartvestor", category: "InputProcessor")) {
        self.logger = logger
    }

    public func startProcessing(
        fd: Int32,
        continuation: AsyncStream<KeyEvent>.Continuation
    ) async {
        self.continuation = continuation
        isActive = true

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.readLoop(fd: fd)
            }

            group.addTask {
                await self.setupTimeoutTimer()
            }
        }

        continuation.finish()
    }

    public func stop() {
        isActive = false
        timeoutTimer?.cancel()
        timeoutTimer = nil
        buffer.removeAll()
    }

    private func setupTimeoutTimer() async {
        while isActive {
            try? await Task.sleep(nanoseconds: UInt64(self.timeoutInterval * 1_000_000_000))

            if !self.buffer.isEmpty {
                logger.fault("Input sequence timeout after \(self.timeoutInterval)s. Clearing incomplete buffer.")
                self.buffer.removeAll()
            }
        }
    }

    private func readLoop(fd: Int32) async {
        let readBufferSize = min(256, Self.MAX_INPUT_SEQUENCE_LENGTH)
        var readBuffer = [UInt8](repeating: 0, count: readBufferSize)

        while isActive {
            let bytesRead = performSelectAndRead(fd: fd, buffer: &readBuffer)

            guard bytesRead > 0 else {
                if bytesRead < 0 {
                    let currentErrno = errno
                    if currentErrno != EAGAIN && currentErrno != EWOULDBLOCK && currentErrno != EINTR {
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
                continue
            }

            let newData = Data(readBuffer.prefix(bytesRead))
            buffer.append(newData)

            if buffer.count > Self.MAX_INPUT_SEQUENCE_LENGTH {
                logger.fault("Input sequence exceeds MAX_INPUT_SEQUENCE_LENGTH (\(Self.MAX_INPUT_SEQUENCE_LENGTH) bytes). Rejecting malformed sequence.")
                buffer.removeAll()
                continue
            }

            while processBuffer() {
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func performSelectAndRead(fd: Int32, buffer: inout [UInt8]) -> Int {
        #if os(macOS) || os(Linux)
        var readFds = fd_set()
        var timeout = timeval(tv_sec: 0, tv_usec: 10000)

        withUnsafeMutablePointer(to: &readFds) { fdSetPtr in
            memset(fdSetPtr, 0, MemoryLayout<fd_set>.size)
            fdSetPtr.pointee.fds_bits.0 = 1 << (fd % 32)
        }

        var result: Int32 = 0
        withUnsafeMutablePointer(to: &readFds) { readFdsPtr in
            withUnsafeMutablePointer(to: &timeout) { timeoutPtr in
                result = select(fd + 1, readFdsPtr, nil, nil, timeoutPtr)
            }
        }

        guard result > 0 else {
            return 0
        }

        var isSet = false
        withUnsafePointer(to: &readFds) { fdSetPtr in
            isSet = (fdSetPtr.pointee.fds_bits.0 & (1 << (fd % 32))) != 0
        }

        guard isSet else {
            return 0
        }

        let maxRead = min(buffer.count, Self.MAX_INPUT_SEQUENCE_LENGTH - self.buffer.count)
        guard maxRead > 0 else {
            return 0
        }

        return read(fd, &buffer, maxRead)
        #else
        return 0
        #endif
    }

    @discardableResult
    private func processBuffer() -> Bool {
        guard !buffer.isEmpty else { return false }

        var bytesConsumed = 0

        self.buffer.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            let count = bytes.count

            guard count > 0 else { return }

            let bytePtr = baseAddress.assumingMemoryBound(to: UInt8.self)

            if let (event, consumed) = self.parseKeyEvent(bytePtr: bytePtr, count: count) {
                self.continuation?.yield(event)
                bytesConsumed = consumed
            }
        }

        if bytesConsumed > 0 {
            self.buffer.removeFirst(bytesConsumed)
            return true
        } else if self.buffer.count >= Self.MAX_INPUT_SEQUENCE_LENGTH {
            logger.fault("Failed to parse input sequence of \(self.buffer.count) bytes. Rejecting malformed sequence.")
            self.buffer.removeAll()
            return false
        }

        return false
    }

    func parseKeyEvent(bytePtr: UnsafePointer<UInt8>, count: Int) -> (KeyEvent, Int)? {
        guard count > 0 else { return nil }

        guard bytePtr[0] == 27 else {
            if let (event, consumed) = parseNonEscapeSequence(bytePtr: bytePtr, count: count) {
                return (event, consumed)
            }
            return nil
        }

        guard count >= 2 else {
            return nil
        }

        if count >= 3 && bytePtr[1] == 91 {
            guard count >= 3 else { return nil }

            if bytePtr[2] == 60 {
                return parseMouseSequence(bytePtr: bytePtr, count: count)
            }

            let event: KeyEvent
            switch bytePtr[2] {
            case 65:
                event = .arrowUp
            case 66:
                event = .arrowDown
            case 67:
                event = .arrowRight
            case 68:
                event = .arrowLeft
            default:
                event = .unknown(Array(UnsafeBufferPointer(start: bytePtr, count: min(count, Self.MAX_INPUT_SEQUENCE_LENGTH))))
            }
            return (event, 3)
        } else if count >= 2 && bytePtr[1] == 77 {
            return parseOldMouseSequence(bytePtr: bytePtr, count: count)
        } else if count >= 2 && bytePtr[1] == 27 {
            return (.escape, 2)
        } else {
            return (.escape, 1)
        }
    }

    func parseNonEscapeSequence(bytePtr: UnsafePointer<UInt8>, count: Int) -> (KeyEvent, Int)? {
        guard count > 0 else { return nil }

        if bytePtr[0] == 13 || bytePtr[0] == 10 {
            return (.enter, 1)
        }

        if bytePtr[0] == 127 || bytePtr[0] == 8 {
            return (.backspace, 1)
        }

        if bytePtr[0] == 9 {
            return (.tab, 1)
        }

        if bytePtr[0] < 32 {
            if bytePtr[0] >= 1 && bytePtr[0] <= 26 {
                let charValue = Int(bytePtr[0]) + 96
                if let char = Unicode.Scalar(charValue).map(Character.init) {
                    return (.control(char), 1)
                }
            }
            return (.unknown(Array(UnsafeBufferPointer(start: bytePtr, count: min(count, Self.MAX_INPUT_SEQUENCE_LENGTH)))), 1)
        }

        var utf8Length = 1
        if bytePtr[0] & 0x80 != 0 {
            if bytePtr[0] & 0xE0 == 0xC0 && count >= 2 {
                utf8Length = 2
            } else if bytePtr[0] & 0xF0 == 0xE0 && count >= 3 {
                utf8Length = 3
            } else if bytePtr[0] & 0xF8 == 0xF0 && count >= 4 {
                utf8Length = 4
            } else {
                logger.fault("Invalid UTF-8 sequence start byte: 0x\(String(bytePtr[0], radix: 16))")
                return nil
            }
        }

        guard count >= utf8Length else {
            return nil
        }

        let data = Data(bytes: bytePtr, count: utf8Length)
        if let string = String(data: data, encoding: .utf8),
           let char = string.first,
           string.count == 1 {
            return (.character(char), utf8Length)
        }

        logger.fault("Failed to decode UTF-8 sequence of \(utf8Length) bytes. Rejecting malformed input.")
        return nil
    }

    func parseMouseSequence(bytePtr: UnsafePointer<UInt8>, count: Int) -> (KeyEvent, Int)? {
        guard count >= 6 else { return nil }

        var idx = 3
        while idx < count && bytePtr[idx] != 109 && bytePtr[idx] != 77 {
            if bytePtr[idx] < 48 || bytePtr[idx] > 57 {
                break
            }
            idx += 1
        }

        if idx < count && (bytePtr[idx] == 109 || bytePtr[idx] == 77) {
            return (.unknown([]), idx + 1)
        }

        if idx >= count {
            return nil
        }

        return (.unknown([]), min(idx + 1, count))
    }

    func parseOldMouseSequence(bytePtr: UnsafePointer<UInt8>, count: Int) -> (KeyEvent, Int)? {
        guard count >= 3 else { return nil }
        return (.unknown([]), 3)
    }
}
