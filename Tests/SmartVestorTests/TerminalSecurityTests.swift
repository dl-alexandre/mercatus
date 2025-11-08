import Testing
import Foundation
@testable import SmartVestor
import Utils

#if os(macOS) || os(Linux)
import Darwin
#endif

@Suite("Terminal Security Tests")
struct TerminalSecurityTests {


    @Test("TerminalSecurity should sanitize ANSI escape sequences from input")
    func testANSIEscapeSequenceSanitization() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let maliciousInput = "Hello\u{001B}[31mWorld\u{001B}[0m"
        let sanitized = security.sanitizeInput(maliciousInput)

        #expect(sanitized != maliciousInput)
        #expect(!sanitized.contains("\u{001B}"))
        #expect(sanitized.contains("Hello"))
        #expect(sanitized.contains("World"))
    }

    @Test("TerminalSecurity should sanitize CSI escape sequences")
    func testCSIEscapeSequenceSanitization() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let maliciousInput = "Test\u{009B}2J\u{009B}H"
        let sanitized = security.sanitizeInput(maliciousInput)

        #expect(!sanitized.contains("\u{009B}"))
        #expect(sanitized.contains("Test"))
    }

    @Test("TerminalSecurity should preserve safe control characters")
    func testSafeControlCharacterPreservation() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let inputWithSafeChars = "Line1\nLine2\tIndented\r\nLine3"
        let sanitized = security.sanitizeInput(inputWithSafeChars)

        #expect(sanitized.contains("\n"))
        #expect(sanitized.contains("\t"))
        let containsCarriageReturn = sanitized.unicodeScalars.contains { $0.value == 13 }
        #expect(containsCarriageReturn)
    }

    @Test("TerminalSecurity should sanitize server strings strictly")
    func testServerStringSanitization() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let maliciousServerString = "Asset: \u{001B}[32mBTC\u{001B}[0m Price: $50000"
        let sanitized = security.sanitizeServerString(maliciousServerString)

        #expect(!sanitized.contains("\u{001B}"))
        #expect(!sanitized.contains("\u{009B}"))
        #expect(sanitized.contains("Asset:"))
        #expect(sanitized.contains("BTC"))
        #expect(sanitized.contains("Price:"))
        #expect(sanitized.contains("$50000"))
    }

    @Test("TerminalSecurity should remove dangerous control characters from server strings")
    func testDangerousControlCharacterRemoval() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let dangerousInput = "Hello\u{0001}World\u{0007}Test\u{001F}"
        let sanitized = security.sanitizeServerString(dangerousInput)

        #expect(!sanitized.contains("\u{0001}"))
        #expect(!sanitized.contains("\u{0007}"))
        #expect(!sanitized.contains("\u{001F}"))
        #expect(sanitized.contains("Hello"))
        #expect(sanitized.contains("World"))
        #expect(sanitized.contains("Test"))
    }

    @Test("TerminalSecurity should remove DEL character")
    func testDELCharacterRemoval() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let inputWithDEL = "Test\u{007F}Value"
        let sanitized = security.sanitizeServerString(inputWithDEL)

        #expect(!sanitized.contains("\u{007F}"))
        #expect(sanitized.contains("Test"))
        #expect(sanitized.contains("Value"))
    }

    @Test("TerminalSecurity should remove C1 control characters")
    func testC1ControlCharacterRemoval() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let inputWithC1 = "Hello\u{0080}World\u{009F}Test"
        let sanitized = security.sanitizeServerString(inputWithC1)

        #expect(!sanitized.contains("\u{0080}"))
        #expect(!sanitized.contains("\u{009F}"))
        #expect(sanitized.contains("Hello"))
        #expect(sanitized.contains("World"))
        #expect(sanitized.contains("Test"))
    }

    @Test("TerminalSecurity should validate file descriptors")
    func testFileDescriptorValidation() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let stdinFd = FileHandle.standardInput.fileDescriptor
        let stdoutFd = FileHandle.standardOutput.fileDescriptor
        let stderrFd = FileHandle.standardError.fileDescriptor

        #expect(stdinFd >= 0)
        #expect(stdoutFd >= 0)
        #expect(stderrFd >= 0)

        security.cleanupFileDescriptors()

        #expect(fcntl(stdinFd, F_GETFD) >= 0 || errno == EBADF)
        #expect(fcntl(stdoutFd, F_GETFD) >= 0 || errno == EBADF)
        #expect(fcntl(stderrFd, F_GETFD) >= 0 || errno == EBADF)
    }




    @Test("TerminalSecurity should sanitize complex malicious input")
    func testComplexMaliciousInput() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let complexMalicious = """
        \u{001B}[2J\u{001B}[H\u{001B}[31mMALICIOUS\u{001B}[0m
        Asset: \u{009B}32mBTC\u{009B}0m
        Price: $50000\u{0007}\u{0001}
        """

        let sanitized = security.sanitizeServerString(complexMalicious)

        #expect(!sanitized.contains("\u{001B}"))
        #expect(!sanitized.contains("\u{009B}"))
        #expect(!sanitized.contains("\u{0007}"))
        #expect(!sanitized.contains("\u{0001}"))
        #expect(sanitized.contains("Asset:"))
        #expect(sanitized.contains("BTC"))
        #expect(sanitized.contains("Price:"))
        #expect(sanitized.contains("$50000"))
    }

    @Test("TerminalSecurity should preserve normal text")
    func testNormalTextPreservation() {
        let logger = StructuredLogger()
        let security = TerminalSecurity(logger: logger)

        let normalText = "This is normal text with numbers 12345 and symbols !@#$%"
        let sanitized = security.sanitizeServerString(normalText)

        #expect(sanitized == normalText)
    }
}
