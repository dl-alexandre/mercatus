import Testing
import Foundation
@testable import SmartVestor

actor RenderIntentCollector {
    var intents: [RenderIntent] = []
    func append(_ intent: RenderIntent) {
        intents.append(intent)
    }
}

@Suite("Declarative API Tests")
struct DeclarativeAPITests {
    @Test
    func text_component_renders() {
        let text = Text("Hello, World!")
        let size = Size(width: 80, height: 24)
        let measured = text.measure(in: size)

        #expect(measured.width >= 13)
        #expect(measured.height == 1)

        var buffer = TerminalBuffer.empty(size: size)
        text.render(into: &buffer, at: .zero)

        let line0 = String(decoding: buffer.lines[0].utf8, as: UTF8.self)
        #expect(line0.hasPrefix("Hello, World!"))
    }

    @Test
    func vstack_measures_children() {
        let stack = VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
        }

        let size = Size(width: 80, height: 24)
        let measured = stack.measure(in: size)

        #expect(measured.height >= 3)
        #expect(measured.width >= 6)
    }

    @Test
    func vstack_renders_vertically() {
        let stack = VStack {
            Text("First")
            Text("Second")
        }

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        stack.render(into: &buffer, at: .zero)

        let line0 = String(decoding: buffer.lines[0].utf8, as: UTF8.self)
        let line1 = String(decoding: buffer.lines[1].utf8, as: UTF8.self)

        #expect(line0.hasPrefix("First"))
        #expect(line1.hasPrefix("Second"))
    }

    @Test
    func hstack_measures_horizontally() {
        let stack = HStack {
            Text("A")
            Text("B")
            Text("C")
        }

        let size = Size(width: 80, height: 24)
        let measured = stack.measure(in: size)

        #expect(measured.width >= 3)
        #expect(measured.height == 1)
    }

    @Test
    func tui_state_updates_trigger_intent() async {
    let state = TUIState<String>(wrappedValue: "initial")
    let collector = RenderIntentCollector()

    let task = Task { @Sendable in
    var count = 0
    for await intent in state.intentStream() {
    await collector.append(intent)
    count += 1
    if count >= 2 {
    break
    }
    }
    }

        state.setRootBuilder {
            Text(state.wrappedValue)
        }

        state.wrappedValue = "updated"

        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        let receivedIntents = await collector.intents
        #expect(receivedIntents.count >= 1)
        if let firstIntent = receivedIntents.first {
            let root = firstIntent.root
            var buffer = TerminalBuffer.empty(size: Size(width: 80, height: 24))
            root.render(into: &buffer, at: .zero)
            let content = String(decoding: buffer.lines[0].utf8, as: UTF8.self)
            #expect(content.contains("updated") || content.contains("initial"))
        }
    }

    @Test
    func status_view_example() {
        let view = StatusView(uptime: "1:23:45")
        let size = Size(width: 80, height: 24)

        let measured = view.measure(in: size)
        #expect(measured.height >= 2)

        var buffer = TerminalBuffer.empty(size: size)
        view.render(into: &buffer, at: .zero)

        let hasStatus = buffer.lines.prefix(2).contains { line in
            let text = String(decoding: line.utf8, as: UTF8.self)
            return text.contains("System Status") || text.contains("1:23:45")
        }
        #expect(hasStatus)
    }
}
