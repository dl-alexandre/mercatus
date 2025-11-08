import Foundation
import Testing
@testable import SmartVestor

@Suite("Status Panel Migration Tests")
struct StatusPanelMigrationTests {
    @Test
    func status_declarative_80x24() async throws {
        setenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let size = Size(width: 80, height: 24)
        let update = makeSampleUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 8)
        let colorManager = ColorManager()
        let statusView = StatusPanelView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        var buffer = TerminalBuffer.empty(size: size)
        statusView.render(into: &buffer, at: Point(x: 0, y: 0))

        assertSnapshot(buffer: buffer, named: "status_declarative_80x24", testIdentifier: "status_declarative_80x24")
    }

    @Test
    func status_legacy_80x24() async throws {
        unsetenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE")
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let update = makeSampleUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 8)
        let colorManager = ColorManager()
        let renderer = StatusPanelRenderer()

        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let adapter = PanelAdapter(
            panelType: .status,
            renderedLines: renderedPanel.lines,
            layout: layout
        )

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &buffer, at: Point(x: 0, y: 0))

        assertSnapshot(buffer: buffer, named: "status_legacy_80x24", testIdentifier: "status_legacy_80x24")
    }

    @Test
    func status_equivalence_check() async throws {
        let update = makeSampleUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 8)
        let colorManager = ColorManager()
        let size = Size(width: 80, height: 24)

        setenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        var declBuffer = TerminalBuffer.empty(size: size)
        let declView = StatusPanelView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )
        declView.render(into: &declBuffer, at: Point.zero)

        unsetenv("SMARTVESTOR_TUI_STATUS_DECLARATIVE")
        let renderer = StatusPanelRenderer()
        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )
        let adapter = PanelAdapter(
            panelType: .status,
            renderedLines: renderedPanel.lines,
            layout: layout
        )
        var legacyBuffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &legacyBuffer, at: Point.zero)

        let declNormalized = normalizeBufferOutput(declBuffer).serializeUTF8()
        let legacyNormalized = normalizeBufferOutput(legacyBuffer).serializeUTF8()

        let diff = declNormalized != legacyNormalized
        if diff {
            let declPath = snapshotPath(named: "status_declarative_actual")
            let legacyPath = snapshotPath(named: "status_legacy_actual")
            try? declNormalized.write(to: declPath)
            try? legacyNormalized.write(to: legacyPath)
            Issue.record("Status panel equivalence check failed. See .actual files for details.")
        }

        #expect(!diff, "Declarative and legacy should produce equivalent output")
    }
}
