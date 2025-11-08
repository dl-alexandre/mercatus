import Testing
import Foundation
@testable import SmartVestor

@Suite("TUI Config Tests")
struct TUIConfigTests {

    @Test("TUIConfig should have sensible defaults")
    func testDefaultConfig() {
        let config = TUIConfig.default

        #expect(config.display.monochrome == false)
        #expect(config.display.colorMode == .auto)
        #expect(config.display.unicodeMode == .auto)
        #expect(config.layout.minimumWidth == 80)
        #expect(config.layout.minimumHeight == 24)
        #expect(config.refresh.maxRefreshRate == 2.0)
        #expect(config.refresh.updateInterval == 0.5)
        #expect(config.refresh.debounceDelay == 0.1)
        #expect(config.panels.showStatus == true)
        #expect(config.panels.showBalances == true)
        #expect(config.panels.showActivity == true)
        #expect(config.panels.showCommandBar == true)
    }

    @Test("TUIConfig should load with default values when no configs exist")
    func testLoadDefaults() {
        let loader = TUIConfigLoader(environment: [:], fileManager: TestFileManager())
        let (config, warnings) = loader.load()

        #expect(warnings.isEmpty)
        #expect(config.layout.minimumWidth == 80)
        #expect(config.layout.minimumHeight == 24)
        #expect(config.refresh.maxRefreshRate == 2.0)
    }

    @Test("TUIConfig should load from environment variables")
    func testLoadFromEnvironment() {
        let environment: [String: String] = [
            "TUI_MONOCHROME": "true",
            "TUI_MIN_WIDTH": "100",
            "TUI_MIN_HEIGHT": "30",
            "TUI_MAX_REFRESH_RATE": "5.0",
            "TUI_UPDATE_INTERVAL": "0.2"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: TestFileManager())
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.layout.minimumWidth == 100)
        #expect(config.layout.minimumHeight == 30)
        #expect(config.refresh.maxRefreshRate == 5.0)
        #expect(config.refresh.updateInterval == 0.2)
    }

    @Test("TUIConfig should merge environment overrides correctly")
    func testEnvironmentOverrideMerging() {
        let environment: [String: String] = [
            "TUI_COLOR_MODE": "disabled",
            "TUI_UNICODE_MODE": "enabled"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: TestFileManager())
        let (config, _) = loader.load()

        #expect(config.display.colorMode == .disabled)
        #expect(config.display.unicodeMode == .enabled)
        #expect(config.layout.minimumWidth == 80)
    }

    @Test("TUIConfig should load from project config file")
    func testLoadFromProjectConfig() throws {
        let testFileManager = TestFileManager()
        let projectConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: false),
            layout: TUIConfig.LayoutConfig(minimumWidth: 120, minimumHeight: 40),
            refresh: TUIConfig.RefreshConfig(maxRefreshRate: 3.0),
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(projectConfig)

        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.layout.minimumWidth == 120)
        #expect(config.layout.minimumHeight == 40)
        #expect(config.refresh.maxRefreshRate == 3.0)
    }

    @Test("TUIConfig should load from user config file")
    func testLoadFromUserConfig() throws {
        let testFileManager = TestFileManager()
        let userConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: true),
            layout: TUIConfig.LayoutConfig(minimumWidth: 100, minimumHeight: 30),
            refresh: TUIConfig.RefreshConfig(updateInterval: 1.0),
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(userConfig)

        let homeURL = testFileManager.homeDirectoryForCurrentUser
        let userConfigPath = homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path
        testFileManager.addFile(path: userConfigPath, content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.layout.minimumWidth == 100)
        #expect(config.layout.minimumHeight == 30)
        #expect(config.refresh.updateInterval == 1.0)
    }

    @Test("TUIConfig should prioritize environment over project config")
    func testEnvironmentOverProject() throws {
        let testFileManager = TestFileManager()
        let projectConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: false),
            layout: TUIConfig.LayoutConfig(minimumWidth: 100),
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(projectConfig)
        testFileManager.addFile(path: "tui-config.json", content: data)

        let environment: [String: String] = [
            "TUI_MONOCHROME": "true",
            "TUI_MIN_WIDTH": "150"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.layout.minimumWidth == 150)
    }

    @Test("TUIConfig should prioritize environment over user config")
    func testEnvironmentOverUser() throws {
        let testFileManager = TestFileManager()
        let userConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: false),
            layout: TUIConfig.LayoutConfig(minimumWidth: 100),
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(userConfig)
        let homeURL = testFileManager.homeDirectoryForCurrentUser
        let userConfigPath = homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path
        testFileManager.addFile(path: userConfigPath, content: data)

        let environment: [String: String] = [
            "TUI_MONOCHROME": "true",
            "TUI_MIN_WIDTH": "150"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.layout.minimumWidth == 150)
    }

    @Test("TUIConfig should prioritize project over user config")
    func testProjectOverUser() throws {
        let testFileManager = TestFileManager()

        let userConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: false),
            layout: TUIConfig.LayoutConfig(minimumWidth: 100),
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        let projectConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: true),
            layout: TUIConfig.LayoutConfig(minimumWidth: 120),
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        let userData = try encoder.encode(userConfig)
        let projectData = try encoder.encode(projectConfig)

        let homeURL = testFileManager.homeDirectoryForCurrentUser
        let userConfigPath = homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path
        testFileManager.addFile(path: userConfigPath, content: userData)
        testFileManager.addFile(path: "tui-config.json", content: projectData)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.layout.minimumWidth == 120)
    }

    @Test("TUIConfig should validate and clamp minimum width")
    func testValidateMinimumWidth() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 50, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "layout.minimumWidth" })
        #expect(config.layout.minimumWidth == 80)
    }

    @Test("TUIConfig should validate and clamp minimum height")
    func testValidateMinimumHeight() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 15, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "layout.minimumHeight" })
        #expect(config.layout.minimumHeight == 24)
    }

    @Test("TUIConfig should validate and clamp refresh rate")
    func testValidateRefreshRate() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 15.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "refresh.maxRefreshRate" })
        #expect(config.refresh.maxRefreshRate == 10.0)
    }

    @Test("TUIConfig should validate and clamp update interval")
    func testValidateUpdateInterval() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 10.0, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "refresh.updateInterval" })
        #expect(config.refresh.updateInterval == 5.0)
    }

    @Test("TUIConfig should validate and clamp sparkline width")
    func testValidateSparklineWidth() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 150, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "sparkline.sparklineWidth" })
        #expect(config.sparkline.sparklineWidth == 100)
    }

    @Test("TUIConfig should validate and clamp sparkline history length")
    func testValidateSparklineHistoryLength() throws {
        let testFileManager = TestFileManager()
        let invalidJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 2000, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """
        let data = invalidJSON.data(using: .utf8)!
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        #expect(warnings.contains { $0.field == "sparkline.historyLength" })
        #expect(config.sparkline.historyLength == 1000)
    }

    @Test("TUIConfig should validate sparkline height constraints")
    func testValidateSparklineHeight() throws {
        let testFileManager = TestFileManager()
        let invalidConfig = TUIConfig(
            display: .default,
            layout: .default,
            refresh: .default,
            sparkline: SparklineConfig(minHeight: 10, maxHeight: 5),
            panels: .default
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(invalidConfig)
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 1)
        let maxHeightWarning = warnings.first { $0.field == "sparkline.maxHeight" }
        #expect(maxHeightWarning != nil)
        #expect(config.sparkline.maxHeight >= config.sparkline.minHeight)
    }

    @Test("TUIConfig should warn about incompatible refresh settings")
    func testIncompatibleRefreshSettings() throws {
        let testFileManager = TestFileManager()
        let invalidConfig = TUIConfig(
            display: .default,
            layout: .default,
            refresh: TUIConfig.RefreshConfig(maxRefreshRate: 2.0, updateInterval: 0.1),
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(invalidConfig)
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (_, warnings) = loader.load()

        let refreshWarning = warnings.first { $0.field == "refresh" }
        #expect(refreshWarning != nil)
    }

    @Test("TUIConfig should save user preferences")
    func testSaveUserPreferences() throws {
        let testFileManager = TestFileManager()
        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)

        let customConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: true),
            layout: TUIConfig.LayoutConfig(minimumWidth: 120, minimumHeight: 40),
            refresh: TUIConfig.RefreshConfig(maxRefreshRate: 3.0, updateInterval: 0.3),
            sparkline: SparklineConfig(sparklineWidth: 30),
            panels: TUIConfig.PanelsConfig(showStatus: true, showBalances: true, showActivity: false)
        )

        try loader.saveUserPreferences(customConfig)

        let loadedConfig = loader.loadUserPreferences()
        #expect(loadedConfig != nil)
        #expect(loadedConfig?.display.monochrome == true)
        #expect(loadedConfig?.layout.minimumWidth == 120)
        #expect(loadedConfig?.layout.minimumHeight == 40)
        #expect(loadedConfig?.refresh.maxRefreshRate == 3.0)
        #expect(loadedConfig?.refresh.updateInterval == 0.3)
        #expect(loadedConfig?.sparkline.sparklineWidth == 30)
        #expect(loadedConfig?.panels.showActivity == false)
    }

    @Test("TUIConfig should persist user preferences between sessions")
    func testPersistUserPreferences() throws {
        let testFileManager = TestFileManager()

        let originalLoader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let customConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: true),
            layout: TUIConfig.LayoutConfig(minimumWidth: 100),
            refresh: TUIConfig.RefreshConfig(updateInterval: 1.0),
            sparkline: .default,
            panels: .default
        )

        try originalLoader.saveUserPreferences(customConfig)

        let newLoader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (loadedConfig, _) = newLoader.load()

        #expect(loadedConfig.display.monochrome == true)
        #expect(loadedConfig.layout.minimumWidth == 100)
        #expect(loadedConfig.refresh.updateInterval == 1.0)
    }

    @Test("TUIConfig should clear user preferences")
    func testClearUserPreferences() throws {
        let testFileManager = TestFileManager()
        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)

        let customConfig = TUIConfig(
            display: TUIConfig.DisplayConfig(monochrome: true),
            layout: .default,
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        try loader.saveUserPreferences(customConfig)
        #expect(loader.loadUserPreferences() != nil)

        try loader.clearUserPreferences()
        #expect(loader.loadUserPreferences() == nil)
    }

    @Test("TUIConfig should handle invalid panel priorities gracefully")
    func testInvalidPanelPriorities() throws {
        let testFileManager = TestFileManager()
        let invalidConfig = TUIConfig(
            display: .default,
            layout: TUIConfig.LayoutConfig(
                minimumWidth: 80,
                minimumHeight: 24,
                panelPriorities: ["invalid": "critical", "status": "critical"]
            ),
            refresh: .default,
            sparkline: .default,
            panels: .default
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(invalidConfig)
        testFileManager.addFile(path: "tui-config.json", content: data)

        let loader = TUIConfigLoader(environment: [:], fileManager: testFileManager)
        let (_, warnings) = loader.load()

        let invalidPriorityWarning = warnings.first { $0.field.contains("panelPriorities") && $0.message.contains("invalid") }
        #expect(invalidPriorityWarning != nil)
    }

    @Test("TUIConfig should load and merge all configuration sources")
    func testFullHierarchicalMerging() throws {
        let testFileManager = TestFileManager()

        let userJSON = """
        {
            "display": {"monochrome": false, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 100, "minimumHeight": 24, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 2.0, "updateInterval": 1.0, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """

        let projectJSON = """
        {
            "display": {"monochrome": true, "colorMode": "auto", "unicodeMode": "auto"},
            "layout": {"minimumWidth": 80, "minimumHeight": 30, "panelPriorities": {}, "headerHeight": 3, "footerHeight": 2, "verticalGap": 1},
            "refresh": {"maxRefreshRate": 3.0, "updateInterval": 0.5, "debounceDelay": 0.1},
            "sparkline": {"enabled": true, "showPortfolioHistory": true, "showAssetTrends": true, "historyLength": 60, "sparklineWidth": 20, "minHeight": 1, "maxHeight": 4},
            "panels": {"showStatus": true, "showBalances": true, "showActivity": true, "showCommandBar": true}
        }
        """

        let userData = userJSON.data(using: .utf8)!
        let projectData = projectJSON.data(using: .utf8)!

        let homeURL = testFileManager.homeDirectoryForCurrentUser
        let userConfigPath = homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path
        testFileManager.addFile(path: userConfigPath, content: userData)
        testFileManager.addFile(path: "tui-config.json", content: projectData)

        let environment: [String: String] = [
            "TUI_COLOR_MODE": "disabled"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: testFileManager)
        let (config, _) = loader.load()

        #expect(config.display.monochrome == true)
        #expect(config.display.colorMode == .disabled)
        #expect(config.layout.minimumWidth == 80)
        #expect(config.layout.minimumHeight == 30)
        #expect(config.refresh.maxRefreshRate == 3.0)
        #expect(config.refresh.updateInterval == 0.5)
    }

    @Test("TUIConfig should validate configuration on load")
    func testValidationOnLoad() {
        let environment: [String: String] = [
            "TUI_MIN_WIDTH": "50",
            "TUI_MIN_HEIGHT": "15",
            "TUI_MAX_REFRESH_RATE": "20.0"
        ]

        let loader = TUIConfigLoader(environment: environment, fileManager: TestFileManager())
        let (config, warnings) = loader.load()

        #expect(warnings.count >= 3)
        #expect(config.layout.minimumWidth == 80)
        #expect(config.layout.minimumHeight == 24)
        #expect(config.refresh.maxRefreshRate == 10.0)
    }
}

class TestFileManager: FileManager {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private var createdFiles: [String] = []

    func addFile(path: String, content: Data) {
        files[path] = content
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty && dir != "." {
            directories.insert(dir)
        }
    }

    override func fileExists(atPath path: String) -> Bool {
        return files[path] != nil || directories.contains(path) || createdFiles.contains(path)
    }

    override func contents(atPath path: String) -> Data? {
        return files[path]
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        directories.insert(url.path)
        if createIntermediates {
            let pathComponents = url.pathComponents
            for i in 1..<pathComponents.count {
                let partialPath = "/" + pathComponents[1...i].joined(separator: "/")
                directories.insert(partialPath)
            }
        }
    }

    override func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        createdFiles.append(path)
        if let data = data {
            files[path] = data
        }
        return true
    }

    override func removeItem(atPath path: String) throws {
        files.removeValue(forKey: path)
        createdFiles.removeAll { $0 == path }
    }

    override var homeDirectoryForCurrentUser: URL {
        return URL(fileURLWithPath: "/tmp/test-home")
    }
}

extension Array where Element == TUIConfigValidationWarning {
    func contains(where predicate: (Element) -> Bool) -> Bool {
        return self.first(where: predicate) != nil
    }
}
