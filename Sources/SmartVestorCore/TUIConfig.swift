import Foundation

public struct TUIConfig: Sendable, Codable {
    public let display: DisplayConfig
    public let layout: LayoutConfig
    public let refresh: RefreshConfig
    public let sparkline: SparklineConfig
    public let panels: PanelsConfig
    public let configVersion: Int
    public let themeVersion: Int

    public static var isTestMode: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CURSOR_TEST"] == "1" ||
               env["CI"] == "1" ||
               env["TEST_MODE"] == "1"
    }

    public init(
        display: DisplayConfig = .default,
        layout: LayoutConfig = .default,
        refresh: RefreshConfig = .default,
        sparkline: SparklineConfig = .default,
        panels: PanelsConfig = .default,
        configVersion: Int = 1,
        themeVersion: Int = 0
    ) {
        self.display = display
        self.layout = layout
        self.refresh = refresh
        self.sparkline = sparkline
        self.panels = panels
        self.configVersion = configVersion
        self.themeVersion = themeVersion
    }

    public static let `default` = TUIConfig()

    public func migrate(from old: TUIConfig) -> TUIConfig {
        var migrated = self
        var log: [String] = []

        if old.configVersion < 1 {
            migrated = TUIConfig(
                display: old.display,
                layout: old.layout,
                refresh: old.refresh,
                sparkline: old.sparkline,
                panels: old.panels,
                configVersion: 1,
                themeVersion: 0
            )
            log.append("Initialized config version to 1")
        }

        if old.configVersion < 2 {
            var updatedSparkline = migrated.sparkline
            if updatedSparkline.graphMode == .default {
                updatedSparkline = SparklineConfig(
                    enabled: updatedSparkline.enabled,
                    showPortfolioHistory: updatedSparkline.showPortfolioHistory,
                    showAssetTrends: updatedSparkline.showAssetTrends,
                    historyLength: updatedSparkline.historyLength,
                    sparklineWidth: updatedSparkline.sparklineWidth,
                    minHeight: updatedSparkline.minHeight,
                    maxHeight: updatedSparkline.maxHeight,
                    graphMode: .default,
                    scalingMode: .auto,
                    fixedMin: nil,
                    fixedMax: nil
                )
                migrated = TUIConfig(
                    display: migrated.display,
                    layout: migrated.layout,
                    refresh: migrated.refresh,
                    sparkline: updatedSparkline,
                    panels: migrated.panels,
                    configVersion: migrated.configVersion,
                    themeVersion: migrated.themeVersion
                )
                log.append("Migrated sparkline.graphMode to default, scalingMode to auto")
            }
        }

        if !log.isEmpty {
            print("Config migration: \(log.joined(separator: ", "))")
        }

        return migrated
    }

    public struct DisplayConfig: Sendable, Codable {
        public let monochrome: Bool
        public let colorMode: ColorMode
        public let unicodeMode: UnicodeMode

        public init(
            monochrome: Bool = false,
            colorMode: ColorMode = .auto,
            unicodeMode: UnicodeMode = .auto
        ) {
            self.monochrome = monochrome
            self.colorMode = colorMode
            self.unicodeMode = unicodeMode
        }

        public static let `default` = DisplayConfig()
    }

    public enum ColorMode: String, Codable, Sendable {
        case auto
        case enabled
        case disabled
    }

    public enum UnicodeMode: String, Codable, Sendable {
        case auto
        case enabled
        case disabled
    }

    public struct LayoutConfig: Sendable, Codable {
        public let minimumWidth: Int
        public let minimumHeight: Int
        public let panelPriorities: [String: String]
        public let headerHeight: Int
        public let footerHeight: Int
        public let verticalGap: Int

        public init(
            minimumWidth: Int = 80,
            minimumHeight: Int = 24,
            panelPriorities: [String: String] = [:],
            headerHeight: Int = 3,
            footerHeight: Int = 2,
            verticalGap: Int = 1
        ) {
            self.minimumWidth = max(80, minimumWidth)
            self.minimumHeight = max(24, minimumHeight)
            self.panelPriorities = panelPriorities
            self.headerHeight = max(1, headerHeight)
            self.footerHeight = max(1, footerHeight)
            self.verticalGap = max(0, verticalGap)
        }

        public static let `default` = LayoutConfig()

        public func toPriorities() -> [PanelType: LayoutPriority] {
            var priorities: [PanelType: LayoutPriority] = [:]
            for (key, value) in panelPriorities {
                guard let panelType = PanelType(rawValue: key) else {
                    continue
                }
                let priority: LayoutPriority?
                switch value.lowercased() {
                case "critical", "0":
                    priority = .critical
                case "high", "1":
                    priority = .high
                case "medium", "2":
                    priority = .medium
                case "low", "3":
                    priority = .low
                default:
                    priority = nil
                }
                if let priority = priority {
                    priorities[panelType] = priority
                }
            }
            if priorities.isEmpty {
                return [
                    .status: .critical,
                    .balances: .high,
                    .balance: .high,
                    .activity: .medium
                ]
            }
            return priorities
        }
    }

    public struct RefreshConfig: Sendable, Codable {
        public let maxRefreshRate: Double
        public let updateInterval: Double
        public let debounceDelay: Double

        public init(
            maxRefreshRate: Double = 2.0,
            updateInterval: Double = 0.5,
            debounceDelay: Double = 0.1
        ) {
            self.maxRefreshRate = max(0.1, min(10.0, maxRefreshRate))
            self.updateInterval = max(0.05, min(5.0, updateInterval))
            self.debounceDelay = max(0.0, min(1.0, debounceDelay))
        }

        public static let `default` = RefreshConfig()
    }

    public struct PanelsConfig: Sendable, Codable {
        public let showStatus: Bool
        public let showBalances: Bool
        public let showActivity: Bool
        public let showCommandBar: Bool

        public init(
            showStatus: Bool = true,
            showBalances: Bool = true,
            showActivity: Bool = true,
            showCommandBar: Bool = true
        ) {
            self.showStatus = showStatus
            self.showBalances = showBalances
            self.showActivity = showActivity
            self.showCommandBar = showCommandBar
        }

        public static let `default` = PanelsConfig()
    }
}

public struct TUIConfigValidationWarning: Sendable {
    public let field: String
    public let message: String
    public let severity: Severity

    public enum Severity: Sendable {
        case warning
        case error
    }

    public init(field: String, message: String, severity: Severity = .warning) {
        self.field = field
        self.message = message
        self.severity = severity
    }
}

public struct TUIConfigLoader: @unchecked Sendable {
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func load() -> (config: TUIConfig, warnings: [TUIConfigValidationWarning]) {
        let environmentConfig = loadFromEnvironment()
        let (projectConfig, projectWarnings) = loadFromProject()
        let (userConfig, userWarnings) = loadFromUser()
        let defaultConfig = TUIConfig.default

        var merged = merge(
            environment: environmentConfig,
            project: projectConfig,
            user: userConfig,
            default: defaultConfig
        )

        var warnings = projectWarnings + userWarnings

        if let envConfig = environmentConfig {
            let envWarnings = validateEnvironmentConfig(envConfig)
            warnings.append(contentsOf: envWarnings)
        }

        let oldConfig = merged
        if oldConfig.configVersion < 1 {
            merged = merged.migrate(from: oldConfig)
        }

        warnings.append(contentsOf: validate(&merged))

        return (merged, warnings)
    }

    public func saveUserPreferences(_ config: TUIConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(config)

        let homeURL = fileManager.homeDirectoryForCurrentUser
        let configDir = homeURL.appendingPathComponent(".config/smartvestor")

        if !fileManager.fileExists(atPath: configDir.path) {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        let configPath = configDir.appendingPathComponent("tui-config.json")
        if !fileManager.createFile(atPath: configPath.path, contents: data, attributes: nil) {
            throw NSError(domain: "TUIConfig", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create config file"])
        }
    }

    public func loadUserPreferences() -> TUIConfig? {
        return loadFromUser().config
    }

    public func clearUserPreferences() throws {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let possiblePaths = [
            homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path,
            homeURL.appendingPathComponent(".smartvestor/tui-config.json").path
        ]

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }
    }

    private func loadFromEnvironment() -> PartialTUIConfig? {
        var partial = PartialTUIConfig()
        var hasAny = false

        if let monochrome = environment["TUI_MONOCHROME"], !monochrome.isEmpty {
            partial.display?.monochrome = (monochrome.lowercased() == "true" || monochrome == "1")
            hasAny = true
        }

        if let colorMode = environment["TUI_COLOR_MODE"], !colorMode.isEmpty {
            if let mode = TUIConfig.ColorMode(rawValue: colorMode.lowercased()) {
                partial.display?.colorMode = mode
                hasAny = true
            }
        }

        if let unicodeMode = environment["TUI_UNICODE_MODE"], !unicodeMode.isEmpty {
            if let mode = TUIConfig.UnicodeMode(rawValue: unicodeMode.lowercased()) {
                partial.display?.unicodeMode = mode
                hasAny = true
            }
        }

        if let minWidth = environment["TUI_MIN_WIDTH"], let width = Int(minWidth) {
            partial.layout?.minimumWidth = width
            hasAny = true
        }

        if let minHeight = environment["TUI_MIN_HEIGHT"], let height = Int(minHeight) {
            partial.layout?.minimumHeight = height
            hasAny = true
        }

        if let maxRefreshRate = environment["TUI_MAX_REFRESH_RATE"], let rate = Double(maxRefreshRate) {
            partial.refresh?.maxRefreshRate = rate
            hasAny = true
        }

        if let updateInterval = environment["TUI_UPDATE_INTERVAL"], let interval = Double(updateInterval) {
            partial.refresh?.updateInterval = interval
            hasAny = true
        }

        if let debounceDelay = environment["TUI_DEBOUNCE_DELAY"], let delay = Double(debounceDelay) {
            partial.refresh?.debounceDelay = delay
            hasAny = true
        }

        return hasAny ? partial : nil
    }

    private func loadFromProject() -> (config: TUIConfig?, warnings: [TUIConfigValidationWarning]) {
        let possiblePaths = [
            ".smartvestor/tui-config.json",
            "config/tui-config.json",
            "tui-config.json"
        ]

        for path in possiblePaths {
            let (config, warnings) = loadFromFile(at: path)
            if let config = config {
                return (config, warnings)
            }
        }

        return (nil, [])
    }

    private func loadFromUser() -> (config: TUIConfig?, warnings: [TUIConfigValidationWarning]) {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let possiblePaths = [
            homeURL.appendingPathComponent(".config/smartvestor/tui-config.json").path,
            homeURL.appendingPathComponent(".smartvestor/tui-config.json").path
        ]

        for path in possiblePaths {
            let (config, warnings) = loadFromFile(at: path)
            if let config = config {
                return (config, warnings)
            }
        }

        return (nil, [])
    }

    private func loadFromFile(at path: String) -> (config: TUIConfig?, rawWarnings: [TUIConfigValidationWarning]) {
        guard fileManager.fileExists(atPath: path) else {
            return (nil, [])
        }

        guard let data = fileManager.contents(atPath: path) else {
            return (nil, [])
        }

        do {
            let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            var rawWarnings: [TUIConfigValidationWarning] = []

            if let layout = rawJSON?["layout"] as? [String: Any] {
                if let minWidth = layout["minimumWidth"] as? Int, minWidth < 80 {
                    rawWarnings.append(TUIConfigValidationWarning(
                        field: "layout.minimumWidth",
                        message: "Minimum width must be at least 80, got \(minWidth). Clamped to 80.",
                        severity: .warning
                    ))
                }
                if let minHeight = layout["minimumHeight"] as? Int, minHeight < 24 {
                    rawWarnings.append(TUIConfigValidationWarning(
                        field: "layout.minimumHeight",
                        message: "Minimum height must be at least 24, got \(minHeight). Clamped to 24.",
                        severity: .warning
                    ))
                }
            }

            if let refresh = rawJSON?["refresh"] as? [String: Any] {
                if let maxRate = refresh["maxRefreshRate"] as? Double {
                    if maxRate < 0.1 || maxRate > 10.0 {
                        let clamped = max(0.1, min(10.0, maxRate))
                        rawWarnings.append(TUIConfigValidationWarning(
                            field: "refresh.maxRefreshRate",
                            message: "Max refresh rate should be between 0.1 and 10.0 Hz, got \(maxRate). Clamped to \(clamped).",
                            severity: .warning
                        ))
                    }
                }
                if let interval = refresh["updateInterval"] as? Double {
                    if interval < 0.05 || interval > 5.0 {
                        let clamped = max(0.05, min(5.0, interval))
                        rawWarnings.append(TUIConfigValidationWarning(
                            field: "refresh.updateInterval",
                            message: "Update interval should be between 0.05 and 5.0 seconds, got \(interval). Clamped to \(clamped).",
                            severity: .warning
                        ))
                    }
                    if let maxRate = refresh["maxRefreshRate"] as? Double {
                        if interval < 1.0 / maxRate {
                            rawWarnings.append(TUIConfigValidationWarning(
                                field: "refresh",
                                message: "Update interval (\(interval)s) is faster than max refresh rate allows (\(1.0 / maxRate)s). Update interval will be limited by refresh rate.",
                                severity: .warning
                            ))
                        }
                    }
                }
            }

            if let sparkline = rawJSON?["sparkline"] as? [String: Any] {
                if let width = sparkline["sparklineWidth"] as? Int, (width < 5 || width > 100) {
                    let clamped = max(5, min(100, width))
                    rawWarnings.append(TUIConfigValidationWarning(
                        field: "sparkline.sparklineWidth",
                        message: "Sparkline width should be between 5 and 100 characters, got \(width). Clamped to \(clamped).",
                        severity: .warning
                    ))
                }
                if let history = sparkline["historyLength"] as? Int, (history < 10 || history > 1000) {
                    let clamped = max(10, min(1000, history))
                    rawWarnings.append(TUIConfigValidationWarning(
                        field: "sparkline.historyLength",
                        message: "Sparkline history length should be between 10 and 1000, got \(history). Clamped to \(clamped).",
                        severity: .warning
                    ))
                }
                if let minH = sparkline["minHeight"] as? Int, (minH < 1 || minH > 8) {
                    let clamped = max(1, min(8, minH))
                    rawWarnings.append(TUIConfigValidationWarning(
                        field: "sparkline.minHeight",
                        message: "Sparkline min height should be between 1 and 8, got \(minH). Clamped to \(clamped).",
                        severity: .warning
                    ))
                }
                if let maxH = sparkline["maxHeight"] as? Int {
                    let minH = (sparkline["minHeight"] as? Int) ?? 1
                    if maxH < minH || maxH > 8 {
                        let clamped = max(minH, min(8, maxH))
                        rawWarnings.append(TUIConfigValidationWarning(
                            field: "sparkline.maxHeight",
                            message: "Sparkline max height should be at least minHeight (\(minH)) and at most 8, got \(maxH). Clamped to \(clamped).",
                            severity: .warning
                        ))
                    }
                }
            }

            let decoder = JSONDecoder()
            let config = try decoder.decode(TUIConfig.self, from: data)
            return (config, rawWarnings)
        } catch {
            return (nil, [])
        }
    }

    private func merge(
        environment: PartialTUIConfig?,
        project: TUIConfig?,
        user: TUIConfig?,
        default defaultConfig: TUIConfig
    ) -> TUIConfig {
        var config = defaultConfig

        if let user = user {
            config = apply(user, to: config)
        }

        if let project = project {
            config = apply(project, to: config)
        }

        if let env = environment {
            config = apply(env, to: config)
        }

        return config
    }

    private func apply(_ source: TUIConfig, to target: TUIConfig) -> TUIConfig {
        return TUIConfig(
            display: TUIConfig.DisplayConfig(
                monochrome: source.display.monochrome,
                colorMode: source.display.colorMode,
                unicodeMode: source.display.unicodeMode
            ),
            layout: TUIConfig.LayoutConfig(
                minimumWidth: source.layout.minimumWidth,
                minimumHeight: source.layout.minimumHeight,
                panelPriorities: source.layout.panelPriorities.isEmpty ? target.layout.panelPriorities : source.layout.panelPriorities,
                headerHeight: source.layout.headerHeight,
                footerHeight: source.layout.footerHeight,
                verticalGap: source.layout.verticalGap
            ),
            refresh: TUIConfig.RefreshConfig(
                maxRefreshRate: source.refresh.maxRefreshRate,
                updateInterval: source.refresh.updateInterval,
                debounceDelay: source.refresh.debounceDelay
            ),
            sparkline: source.sparkline,
            panels: TUIConfig.PanelsConfig(
                showStatus: source.panels.showStatus,
                showBalances: source.panels.showBalances,
                showActivity: source.panels.showActivity,
                showCommandBar: source.panels.showCommandBar
            )
        )
    }

    private func apply(_ partial: PartialTUIConfig, to target: TUIConfig) -> TUIConfig {
        var display = target.display
        if let partialDisplay = partial.display {
            if let monochrome = partialDisplay.monochrome {
                display = TUIConfig.DisplayConfig(
                    monochrome: monochrome,
                    colorMode: partialDisplay.colorMode ?? display.colorMode,
                    unicodeMode: partialDisplay.unicodeMode ?? display.unicodeMode
                )
            } else {
                display = TUIConfig.DisplayConfig(
                    monochrome: display.monochrome,
                    colorMode: partialDisplay.colorMode ?? display.colorMode,
                    unicodeMode: partialDisplay.unicodeMode ?? display.unicodeMode
                )
            }
        }

        var layout = target.layout
        if let partialLayout = partial.layout {
            layout = TUIConfig.LayoutConfig(
                minimumWidth: partialLayout.minimumWidth ?? layout.minimumWidth,
                minimumHeight: partialLayout.minimumHeight ?? layout.minimumHeight,
                panelPriorities: layout.panelPriorities,
                headerHeight: layout.headerHeight,
                footerHeight: layout.footerHeight,
                verticalGap: layout.verticalGap
            )
        }

        var refresh = target.refresh
        if let partialRefresh = partial.refresh {
            refresh = TUIConfig.RefreshConfig(
                maxRefreshRate: partialRefresh.maxRefreshRate ?? refresh.maxRefreshRate,
                updateInterval: partialRefresh.updateInterval ?? refresh.updateInterval,
                debounceDelay: partialRefresh.debounceDelay ?? refresh.debounceDelay
            )
        }

        return TUIConfig(
            display: display,
            layout: layout,
            refresh: refresh,
            sparkline: target.sparkline,
            panels: target.panels
        )
    }

    private func validateEnvironmentConfig(_ partial: PartialTUIConfig) -> [TUIConfigValidationWarning] {
        var warnings: [TUIConfigValidationWarning] = []

        if let layout = partial.layout {
            if let minWidth = layout.minimumWidth, minWidth < 80 {
                warnings.append(TUIConfigValidationWarning(
                    field: "layout.minimumWidth",
                    message: "Minimum width must be at least 80, got \(minWidth). Clamped to 80.",
                    severity: .warning
                ))
            }
            if let minHeight = layout.minimumHeight, minHeight < 24 {
                warnings.append(TUIConfigValidationWarning(
                    field: "layout.minimumHeight",
                    message: "Minimum height must be at least 24, got \(minHeight). Clamped to 24.",
                    severity: .warning
                ))
            }
        }

        if let refresh = partial.refresh {
            if let maxRate = refresh.maxRefreshRate {
                if maxRate < 0.1 || maxRate > 10.0 {
                    let clamped = max(0.1, min(10.0, maxRate))
                    warnings.append(TUIConfigValidationWarning(
                        field: "refresh.maxRefreshRate",
                        message: "Max refresh rate should be between 0.1 and 10.0 Hz, got \(maxRate). Clamped to \(clamped).",
                        severity: .warning
                    ))
                }
            }
            if let interval = refresh.updateInterval {
                if interval < 0.05 || interval > 5.0 {
                    let clamped = max(0.05, min(5.0, interval))
                    warnings.append(TUIConfigValidationWarning(
                        field: "refresh.updateInterval",
                        message: "Update interval should be between 0.05 and 5.0 seconds, got \(interval). Clamped to \(clamped).",
                        severity: .warning
                    ))
                }
            }
        }

        return warnings
    }

    private func validate(_ config: inout TUIConfig) -> [TUIConfigValidationWarning] {
        var warnings: [TUIConfigValidationWarning] = []

        var layout = config.layout
        if layout.minimumWidth < 80 {
            warnings.append(TUIConfigValidationWarning(
                field: "layout.minimumWidth",
                message: "Minimum width must be at least 80, got \(layout.minimumWidth). Clamped to 80.",
                severity: .warning
            ))
            layout = TUIConfig.LayoutConfig(
                minimumWidth: 80,
                minimumHeight: layout.minimumHeight,
                panelPriorities: layout.panelPriorities,
                headerHeight: layout.headerHeight,
                footerHeight: layout.footerHeight,
                verticalGap: layout.verticalGap
            )
        }

        if layout.minimumHeight < 24 {
            warnings.append(TUIConfigValidationWarning(
                field: "layout.minimumHeight",
                message: "Minimum height must be at least 24, got \(layout.minimumHeight). Clamped to 24.",
                severity: .warning
            ))
            layout = TUIConfig.LayoutConfig(
                minimumWidth: layout.minimumWidth,
                minimumHeight: 24,
                panelPriorities: layout.panelPriorities,
                headerHeight: layout.headerHeight,
                footerHeight: layout.footerHeight,
                verticalGap: layout.verticalGap
            )
        }

        var refresh = config.refresh
        if refresh.maxRefreshRate < 0.1 || refresh.maxRefreshRate > 10.0 {
            let clamped = max(0.1, min(10.0, refresh.maxRefreshRate))
            warnings.append(TUIConfigValidationWarning(
                field: "refresh.maxRefreshRate",
                message: "Max refresh rate should be between 0.1 and 10.0 Hz, got \(refresh.maxRefreshRate). Clamped to \(clamped).",
                severity: .warning
            ))
            refresh = TUIConfig.RefreshConfig(
                maxRefreshRate: clamped,
                updateInterval: refresh.updateInterval,
                debounceDelay: refresh.debounceDelay
            )
        }

        if refresh.updateInterval < 0.05 || refresh.updateInterval > 5.0 {
            let clamped = max(0.05, min(5.0, refresh.updateInterval))
            warnings.append(TUIConfigValidationWarning(
                field: "refresh.updateInterval",
                message: "Update interval should be between 0.05 and 5.0 seconds, got \(refresh.updateInterval). Clamped to \(clamped).",
                severity: .warning
            ))
            refresh = TUIConfig.RefreshConfig(
                maxRefreshRate: refresh.maxRefreshRate,
                updateInterval: clamped,
                debounceDelay: refresh.debounceDelay
            )
        }

        if refresh.debounceDelay < 0.0 || refresh.debounceDelay > 1.0 {
            let clamped = max(0.0, min(1.0, refresh.debounceDelay))
            warnings.append(TUIConfigValidationWarning(
                field: "refresh.debounceDelay",
                message: "Debounce delay should be between 0.0 and 1.0 seconds, got \(refresh.debounceDelay). Clamped to \(clamped).",
                severity: .warning
            ))
            refresh = TUIConfig.RefreshConfig(
                maxRefreshRate: refresh.maxRefreshRate,
                updateInterval: refresh.updateInterval,
                debounceDelay: clamped
            )
        }

        if refresh.updateInterval < 1.0 / refresh.maxRefreshRate {
            warnings.append(TUIConfigValidationWarning(
                field: "refresh",
                message: "Update interval (\(refresh.updateInterval)s) is faster than max refresh rate allows (\(1.0 / refresh.maxRefreshRate)s). Update interval will be limited by refresh rate.",
                severity: .warning
            ))
        }

        var sparkline = config.sparkline
        if sparkline.sparklineWidth < 5 || sparkline.sparklineWidth > 100 {
            let clamped = max(5, min(100, sparkline.sparklineWidth))
            warnings.append(TUIConfigValidationWarning(
                field: "sparkline.sparklineWidth",
                message: "Sparkline width should be between 5 and 100 characters, got \(sparkline.sparklineWidth). Clamped to \(clamped).",
                severity: .warning
            ))
            sparkline = SparklineConfig(
                enabled: sparkline.enabled,
                showPortfolioHistory: sparkline.showPortfolioHistory,
                showAssetTrends: sparkline.showAssetTrends,
                historyLength: sparkline.historyLength,
                sparklineWidth: clamped,
                minHeight: sparkline.minHeight,
                maxHeight: sparkline.maxHeight
            )
        }

        if sparkline.historyLength < 10 || sparkline.historyLength > 1000 {
            let clamped = max(10, min(1000, sparkline.historyLength))
            warnings.append(TUIConfigValidationWarning(
                field: "sparkline.historyLength",
                message: "Sparkline history length should be between 10 and 1000, got \(sparkline.historyLength). Clamped to \(clamped).",
                severity: .warning
            ))
            sparkline = SparklineConfig(
                enabled: sparkline.enabled,
                showPortfolioHistory: sparkline.showPortfolioHistory,
                showAssetTrends: sparkline.showAssetTrends,
                historyLength: clamped,
                sparklineWidth: sparkline.sparklineWidth,
                minHeight: sparkline.minHeight,
                maxHeight: sparkline.maxHeight
            )
        }

        if sparkline.minHeight < 1 || sparkline.minHeight > 8 {
            let clamped = max(1, min(8, sparkline.minHeight))
            warnings.append(TUIConfigValidationWarning(
                field: "sparkline.minHeight",
                message: "Sparkline min height should be between 1 and 8, got \(sparkline.minHeight). Clamped to \(clamped).",
                severity: .warning
            ))
            sparkline = SparklineConfig(
                enabled: sparkline.enabled,
                showPortfolioHistory: sparkline.showPortfolioHistory,
                showAssetTrends: sparkline.showAssetTrends,
                historyLength: sparkline.historyLength,
                sparklineWidth: sparkline.sparklineWidth,
                minHeight: clamped,
                maxHeight: sparkline.maxHeight
            )
        }

        if sparkline.maxHeight < sparkline.minHeight || sparkline.maxHeight > 8 {
            let clamped = max(sparkline.minHeight, min(8, sparkline.maxHeight))
            warnings.append(TUIConfigValidationWarning(
                field: "sparkline.maxHeight",
                message: "Sparkline max height should be at least minHeight (\(sparkline.minHeight)) and at most 8, got \(sparkline.maxHeight). Clamped to \(clamped).",
                severity: .warning
            ))
            sparkline = SparklineConfig(
                enabled: sparkline.enabled,
                showPortfolioHistory: sparkline.showPortfolioHistory,
                showAssetTrends: sparkline.showAssetTrends,
                historyLength: sparkline.historyLength,
                sparklineWidth: sparkline.sparklineWidth,
                minHeight: sparkline.minHeight,
                maxHeight: clamped
            )
        }

        for (key, _) in layout.panelPriorities {
            if PanelType(rawValue: key) == nil {
                warnings.append(TUIConfigValidationWarning(
                    field: "layout.panelPriorities.\(key)",
                    message: "Unknown panel type: \(key). Valid types: status, balances, balance, activity",
                    severity: .warning
                ))
            }
        }

        config = TUIConfig(
            display: config.display,
            layout: layout,
            refresh: refresh,
            sparkline: sparkline,
            panels: config.panels
        )

        return warnings
    }
}

private struct PartialTUIConfig {
    struct PartialDisplayConfig {
        var monochrome: Bool?
        var colorMode: TUIConfig.ColorMode?
        var unicodeMode: TUIConfig.UnicodeMode?
    }

    struct PartialLayoutConfig {
        var minimumWidth: Int?
        var minimumHeight: Int?
    }

    struct PartialRefreshConfig {
        var maxRefreshRate: Double?
        var updateInterval: Double?
        var debounceDelay: Double?
    }

    var display: PartialDisplayConfig?
    var layout: PartialLayoutConfig?
    var refresh: PartialRefreshConfig?

    init() {
        self.display = PartialDisplayConfig()
        self.layout = PartialLayoutConfig()
        self.refresh = PartialRefreshConfig()
    }
}
