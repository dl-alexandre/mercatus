import Testing
import Foundation
@testable import SmartVestor
import Utils

@Suite("TUI Client Integration Tests")
struct TUIClientIntegrationTests {

    @Test("TUIConnectionManager should handle connection status updates")
    func testConnectionStatusUpdates() async {
        let logger = StructuredLogger()
        let manager = TUIConnectionManager(socketPath: "/tmp/test.sock", logger: logger)

        actor StatusCollector {
            var statuses: [TUIConnectionStatus] = []
            func append(_ status: TUIConnectionStatus) {
                statuses.append(status)
            }
            func get() -> [TUIConnectionStatus] {
                return statuses
            }
        }

        let collector = StatusCollector()
        let statusTask = Task {
            for await status in manager.connectionStatusStream {
                await collector.append(status)
            }
        }

        await manager.setStatus(TUIConnectionStatus.connecting)
        await manager.setStatus(TUIConnectionStatus.connected)
        await manager.setStatus(TUIConnectionStatus.failed(reason: "Test error"))

        try? await Task.sleep(nanoseconds: 100_000_000)
        statusTask.cancel()

        let statuses = await collector.get()
        #expect(statuses.count >= 3)
        #expect(statuses.contains {
            if case .connecting = $0 { return true }
            return false
        })
        #expect(statuses.contains {
            if case .connected = $0 { return true }
            return false
        })
        #expect(statuses.contains {
            if case .failed = $0 { return true }
            return false
        })
    }

    @Test("TUIConnectionManager should implement exponential backoff")
    func testExponentialBackoff() async {
        let config = BackoffConfiguration(initial: 0.1, multiplier: 2.0, maxDelay: 1.0, maxRetries: 5)
        let logger = StructuredLogger()
        let manager = TUIConnectionManager(socketPath: "/tmp/test.sock", backoffConfig: config, logger: logger)

        await manager.scheduleReconnect()

        let status = await manager.getStatus()
        let isReconnecting = if case .reconnecting = status { true } else { false }
        #expect(isReconnecting)
    }

    @Test("TUIConnectionManager should cache and retrieve frames")
    func testFrameCaching() async {
        let logger = StructuredLogger()
        let manager = TUIConnectionManager(socketPath: "/tmp/test.sock", logger: logger)

        let testFrame = ["Line 1", "Line 2", "Line 3"]
        await manager.cacheFrame(testFrame)

        let cachedFrame = await manager.getCachedFrame()
        #expect(cachedFrame != nil)
        #expect(cachedFrame?.count == 3)
        #expect(cachedFrame?[0] == "Line 1")
    }

    @Test("AlertBannerRenderer should render connection alerts")
    func testAlertBannerRendering() {
        let renderer = AlertBannerRenderer()

        let infoAlert = renderer.renderConnectionAlert(status: TUIConnectionStatus.connecting)
        #expect(!infoAlert.isEmpty)

        let warningAlert = renderer.renderConnectionAlert(status: TUIConnectionStatus.reconnecting)
        #expect(!warningAlert.isEmpty)

        let errorAlert = renderer.renderConnectionAlert(status: TUIConnectionStatus.failed(reason: "Test error"))
        #expect(!errorAlert.isEmpty)

        let connectedAlert = renderer.renderConnectionAlert(status: TUIConnectionStatus.connected)
        #expect(connectedAlert.isEmpty)
    }

    @Test("AlertBannerRenderer should handle different severities")
    func testAlertBannerSeverities() {
        let renderer = AlertBannerRenderer()

        let infoAlert = renderer.renderAlert(message: "Information", severity: .info, width: 80)
        #expect(!infoAlert.isEmpty)

        let warningAlert = renderer.renderAlert(message: "Warning message", severity: .warning, width: 80)
        #expect(!warningAlert.isEmpty)

        let errorAlert = renderer.renderAlert(message: "Error occurred", severity: .error, width: 80)
        #expect(!errorAlert.isEmpty)
    }

    @Test("AlertBannerRenderer should wrap long messages")
    func testAlertBannerTextWrapping() {
        let renderer = AlertBannerRenderer()

        let longMessage = "This is a very long message that should be wrapped across multiple lines when rendered in the alert banner component"
        let alert = renderer.renderAlert(message: longMessage, severity: .info, width: 40)

        #expect(!alert.isEmpty)

        for line in alert {
            #expect(line.count <= 44)
        }
    }
}
