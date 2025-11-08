import Testing
import Foundation
@testable import SmartVestor
import Utils

@Suite("Navigation Tests")
struct NavigationTests {

private func parseKeyEvent(from bytes: [UInt8], using processor: InputProcessor) -> KeyEvent? {
    let data = Data(bytes)
    return data.withUnsafeBytes { ptr in
            if let (event, _) = processor.parseKeyEvent(bytePtr: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), count: data.count) {
                return event
            }
            return nil
        }
    }

    @Test("InputProcessor should parse character keys correctly")
    func testCharacterKeyParsing() {
        let processor = InputProcessor()

        let testCases: [(bytes: [UInt8], expected: KeyEvent)] = [
            ([65], .character("A")),
            ([97], .character("a")),
            ([48], .character("0")),
            ([32], .character(" ")),
            ([64], .character("@")),
        ]

        for (bytes, expected) in testCases {
            if let result = parseKeyEvent(from: bytes, using: processor) {
                if case .character(let char) = result,
                   case .character(let expectedChar) = expected {
                    #expect(char == expectedChar)
                } else {
                    Issue.record("Expected character key for \(bytes), got \(result)")
                }
            } else {
                Issue.record("Failed to parse character key from \(bytes)")
            }
        }
    }

    @Test("InputProcessor should parse arrow keys correctly")
    func testArrowKeyParsing() {
    let processor = InputProcessor()

        let arrowUp: [UInt8] = [27, 91, 65]
        let arrowDown: [UInt8] = [27, 91, 66]
        let arrowRight: [UInt8] = [27, 91, 67]
        let arrowLeft: [UInt8] = [27, 91, 68]

        if let upResult = parseKeyEvent(from: arrowUp, using: processor) {
            #expect(upResult == .arrowUp)
        } else {
            Issue.record("Failed to parse arrow up")
        }

        if let downResult = parseKeyEvent(from: arrowDown, using: processor) {
            #expect(downResult == .arrowDown)
        } else {
            Issue.record("Failed to parse arrow down")
        }

        if let rightResult = parseKeyEvent(from: arrowRight, using: processor) {
            #expect(rightResult == .arrowRight)
        } else {
            Issue.record("Failed to parse arrow right")
        }

        if let leftResult = parseKeyEvent(from: arrowLeft, using: processor) {
            #expect(leftResult == .arrowLeft)
        } else {
            Issue.record("Failed to parse arrow left")
        }
    }

    @Test("InputProcessor should parse special keys correctly")
    func testSpecialKeyParsing() {
    let processor = InputProcessor()

        let enter: [UInt8] = [13]
        let backspace: [UInt8] = [127]
        let escape: [UInt8] = [27, 27]
        let tab: [UInt8] = [9]

        if let enterResult = parseKeyEvent(from: enter, using: processor) {
            #expect(enterResult == .enter)
        } else {
            Issue.record("Failed to parse enter key")
        }

        if let backspaceResult = parseKeyEvent(from: backspace, using: processor) {
            #expect(backspaceResult == .backspace)
        } else {
            Issue.record("Failed to parse backspace key")
        }

        if let escapeResult = parseKeyEvent(from: escape, using: processor) {
            #expect(escapeResult == .escape)
        } else {
            Issue.record("Failed to parse escape key")
        }

        if let tabResult = parseKeyEvent(from: tab, using: processor) {
            #expect(tabResult == .tab)
        } else {
            Issue.record("Failed to parse tab key")
        }
    }

    @Test("InputProcessor should parse control keys correctly")
    func testControlKeyParsing() {
    let processor = InputProcessor()

        let ctrlC: [UInt8] = [3]
        let ctrlD: [UInt8] = [4]
        let ctrlZ: [UInt8] = [26]

        if let ctrlCResult = parseKeyEvent(from: ctrlC, using: processor) {
            if case .control(let char) = ctrlCResult {
                #expect(char == "c")
            } else {
                Issue.record("Expected control key, got \(ctrlCResult)")
            }
        } else {
            Issue.record("Failed to parse Ctrl+C")
        }

        if let ctrlDResult = parseKeyEvent(from: ctrlD, using: processor) {
            if case .control(let char) = ctrlDResult {
                #expect(char == "d")
            } else {
                Issue.record("Expected control key, got \(ctrlDResult)")
            }
        } else {
            Issue.record("Failed to parse Ctrl+D")
        }

        if let ctrlZResult = parseKeyEvent(from: ctrlZ, using: processor) {
            if case .control(let char) = ctrlZResult {
                #expect(char == "z")
            } else {
                Issue.record("Expected control key, got \(ctrlZResult)")
            }
        } else {
            Issue.record("Failed to parse Ctrl+Z")
        }
    }

    @Test("InputProcessor should handle unknown sequences")
    func testUnknownKeySequenceParsing() {
    let processor = InputProcessor()

        let unknown: [UInt8] = [27, 91, 99]
        let result = parseKeyEvent(from: unknown, using: processor)

        if let parsed = result {
            if case .unknown(let bytes) = parsed {
                #expect(bytes == unknown)
            } else {
                Issue.record("Expected unknown key sequence, got \(parsed)")
            }
        } else {
            Issue.record("Failed to parse unknown sequence")
        }
    }

    @Test("NavigationManager should initialize with default focus")
    func testNavigationManagerInitialization() async {
        let manager = NavigationManager()

        await MainActor.run {
            let focus = manager.getCurrentFocus()
            #expect(focus == .status)
        }
    }

    @Test("NavigationManager should set focus correctly")
    func testNavigationManagerSetFocus() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.balance)
            #expect(manager.getCurrentFocus() == .balance)

            manager.setFocus(.activity)
            #expect(manager.getCurrentFocus() == .activity)

            manager.setFocus(.status)
            #expect(manager.getCurrentFocus() == .status)
        }
    }

    @Test("NavigationManager should navigate up and down between panels")
    func testNavigationManagerUpDown() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.status)
            #expect(manager.getCurrentFocus() == .status)

            let downFromStatus = manager.navigate(.down)
            #expect(downFromStatus == .balance)
            #expect(manager.getCurrentFocus() == .balance)

            let downFromBalance = manager.navigate(.down)
            #expect(downFromBalance == .activity)
            #expect(manager.getCurrentFocus() == .activity)

            let downFromActivity = manager.navigate(.down)
            #expect(downFromActivity == nil)
            #expect(manager.getCurrentFocus() == .activity)

            let upFromActivity = manager.navigate(.up)
            #expect(upFromActivity == .balance)
            #expect(manager.getCurrentFocus() == .balance)

            let upFromBalance = manager.navigate(.up)
            #expect(upFromBalance == .status)
            #expect(manager.getCurrentFocus() == .status)

            let upFromStatus = manager.navigate(.up)
            #expect(upFromStatus == nil)
            #expect(manager.getCurrentFocus() == .status)
        }
    }

    @Test("NavigationManager should handle arrow key events")
    func testNavigationManagerHandleNavigation() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.status)

            let handledUp = manager.handleNavigation(.arrowUp)
            #expect(handledUp == false)
            #expect(manager.getCurrentFocus() == .status)

            let handledDown = manager.handleNavigation(.arrowDown)
            #expect(handledDown == true)
            #expect(manager.getCurrentFocus() == .balance)

            let handledDownAgain = manager.handleNavigation(.arrowDown)
            #expect(handledDownAgain == true)
            #expect(manager.getCurrentFocus() == .activity)

            let handledUpNow = manager.handleNavigation(.arrowUp)
            #expect(handledUpNow == true)
            #expect(manager.getCurrentFocus() == .balance)

            let handledLeft = manager.handleNavigation(.arrowLeft)
            #expect(handledLeft == false)

            let handledRight = manager.handleNavigation(.arrowRight)
            #expect(handledRight == false)

            let handledCharacter = manager.handleNavigation(.character("a"))
            #expect(handledCharacter == false)
        }
    }

    @Test("NavigationManager should check focus state correctly")
    func testNavigationManagerIsFocused() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.status)
            #expect(manager.isFocused(.status) == true)
            #expect(manager.isFocused(.balance) == false)
            #expect(manager.isFocused(.activity) == false)

            manager.setFocus(.balance)
            #expect(manager.isFocused(.status) == false)
            #expect(manager.isFocused(.balance) == true)
            #expect(manager.isFocused(.activity) == false)

            manager.setFocus(.activity)
            #expect(manager.isFocused(.status) == false)
            #expect(manager.isFocused(.balance) == false)
            #expect(manager.isFocused(.activity) == true)
        }
    }

    @Test("NavigationManager should map focus to panel types correctly")
    func testNavigationManagerPanelTypeMapping() {
        #expect(PanelFocus.status.panelType == .status)
        #expect(PanelFocus.balance.panelType == .balance)
        #expect(PanelFocus.activity.panelType == .activity)

        #expect(PanelFocus.status.identifier == "status")
        #expect(PanelFocus.balance.identifier == "balance")
        #expect(PanelFocus.activity.identifier == "activity")
    }

    @Test("NavigationManager should persist focus during multiple updates")
    func testFocusPersistenceDuringUpdates() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.balance)
            #expect(manager.getCurrentFocus() == .balance)

            for _ in 0..<10 {
                let current = manager.getCurrentFocus()
                #expect(current == .balance)

            _ = manager.navigate(.down)
            _ = manager.navigate(.up)

                let afterNav = manager.getCurrentFocus()
                #expect(afterNav == .balance)
            }
        }
    }

    @Test("NavigationManager should handle rapid navigation changes")
    func testRapidNavigationChanges() async {
        let manager = NavigationManager()

        await MainActor.run {
            manager.setFocus(.status)

            for i in 0..<20 {
                if i % 2 == 0 {
                    _ = manager.navigate(.down)
                } else {
                    _ = manager.navigate(.up)
                }

                let current = manager.getCurrentFocus()
                #expect(current == .status || current == .balance || current == .activity)
            }

            manager.setFocus(.activity)
            #expect(manager.getCurrentFocus() == .activity)
        }
    }

    @Test("PanelFocus should navigate in correct order")
    func testPanelFocusNavigationOrder() {
        #expect(PanelFocus.status.navigate(direction: .down) == .balance)
        #expect(PanelFocus.balance.navigate(direction: .down) == .activity)
        #expect(PanelFocus.activity.navigate(direction: .down) == nil)

        #expect(PanelFocus.status.navigate(direction: .up) == nil)
        #expect(PanelFocus.balance.navigate(direction: .up) == .status)
        #expect(PanelFocus.activity.navigate(direction: .up) == .balance)

        _ = PanelFocus.status.navigate(direction: .left)
        #expect(PanelFocus.status.navigate(direction: .left) == nil)
        _ = PanelFocus.status.navigate(direction: .right)
        #expect(PanelFocus.status.navigate(direction: .right) == nil)
    }
}
