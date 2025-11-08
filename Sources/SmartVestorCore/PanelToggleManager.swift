import Foundation

public struct PanelToggleConfig: Codable, Sendable {
    public var visibility: [PanelType: Bool]
    public var selectedPanel: PanelType?

    public init(visibility: [PanelType: Bool] = [:], selectedPanel: PanelType? = nil) {
        self.visibility = visibility
        self.selectedPanel = selectedPanel
    }

    public static let `default` = PanelToggleConfig(
        visibility: [
            .status: true,
            .balances: true,
            .balance: true,
            .activity: true,
            .price: true,
            .swap: true,
            .logs: true
        ],
        selectedPanel: .status
    )
}

public actor PanelToggleManager {
    private var visibility: [PanelType: Bool]
    private var selectedPanel: PanelType?
    private let configPath: String
    private let fileManager: FileManager

    public init(configPath: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let defaultVisibility: [PanelType: Bool] = [
            .status: true,
            .balances: true,
            .balance: true,
            .activity: true,
            .price: true,
            .swap: true,
            .logs: true
        ]

        if let path = configPath {
            self.configPath = path
        } else {
            let homeURL = fileManager.homeDirectoryForCurrentUser
            let configDir = homeURL.appendingPathComponent(".config/smartvestor")
            self.configPath = configDir.appendingPathComponent("tui-panel-config.json").path
        }

        if let loaded = Self.loadConfig(from: self.configPath, fileManager: fileManager) {
            self.visibility = loaded.visibility
            self.selectedPanel = loaded.selectedPanel
        } else {
            self.visibility = defaultVisibility
            self.selectedPanel = .status
        }

        for panelType in [PanelType.status, .balances, .balance, .activity, .price, .swap, .logs] {
            self.visibility[panelType] = true
        }

        var visibleCount = 0
        for value in visibility.values {
            if value {
                visibleCount += 1
            }
        }

        if visibleCount == 0 {
            visibility[.status] = true
            selectedPanel = .status
        } else if let selected = selectedPanel {
            let balanceVal = visibility[.balance]
            let balancesVal = visibility[.balances]
            let balanceVisible = (balanceVal == true) || (balancesVal == true)
            var isSelectedVisible = false

            if selected == .balance || selected == .balances {
                isSelectedVisible = balanceVisible
            } else {
                if let vis = visibility[selected] {
                    isSelectedVisible = vis
                } else {
                    isSelectedVisible = false
                }
            }

            if !isSelectedVisible {
                if balanceVisible {
                    selectedPanel = .balances
                } else {
                    let statusVis = visibility[.status]
                    let activityVis = visibility[.activity]
                    let priceVis = visibility[.price]
                    let swapVis = visibility[.swap]
                    if statusVis == true {
                        selectedPanel = .status
                    } else if activityVis == true {
                        selectedPanel = .activity
                    } else if priceVis == true {
                        selectedPanel = .price
                    } else if swapVis == true {
                        selectedPanel = .swap
                    } else {
                        selectedPanel = .status
                    }
                }
            }
        } else {
            let balanceVal = visibility[.balance]
            let balancesVal = visibility[.balances]
            let balanceVisible = (balanceVal == true) || (balancesVal == true)
            if balanceVisible {
                selectedPanel = .balances
            } else {
                let statusVis = visibility[.status]
                let activityVis = visibility[.activity]
                let priceVis = visibility[.price]
                let swapVis = visibility[.swap]
                if statusVis == true {
                    selectedPanel = .status
                } else if activityVis == true {
                    selectedPanel = .activity
                } else if priceVis == true {
                    selectedPanel = .price
                } else if swapVis == true {
                    selectedPanel = .swap
                } else {
                    selectedPanel = .status
                }
            }
        }
    }

    public func isVisible(_ panelType: PanelType) -> Bool {
        if panelType == .balance || panelType == .balances {
            return visibility[.balance] ?? visibility[.balances] ?? false
        }
        return visibility[panelType] ?? false
    }

    public func toggle(_ panelType: PanelType) async throws {
        guard panelType != .custom else {
            throw PanelToggleError.invalidPanelType
        }

        let currentVisibility = isVisible(panelType)

        if panelType == .balance || panelType == .balances {
            visibility[.balance] = !currentVisibility
            visibility[.balances] = !currentVisibility
        } else {
            visibility[panelType] = !currentVisibility
        }

        ensureAtLeastOneVisible()

        try await saveConfig()
    }

    public func setVisibility(_ panelType: PanelType, visible: Bool) async throws {
        guard panelType != .custom else {
            throw PanelToggleError.invalidPanelType
        }

        if panelType == .balance || panelType == .balances {
            visibility[.balance] = visible
            visibility[.balances] = visible
        } else {
            visibility[panelType] = visible
        }

        ensureAtLeastOneVisible()

        try await saveConfig()
    }

    public func getSelectedPanel() -> PanelType? {
        return selectedPanel
    }

    public func setSelectedPanel(_ panelType: PanelType) {
        guard isVisible(panelType) else {
            return
        }
        selectedPanel = panelType
    }

    public func cycleToNextVisiblePanel() {
        let visiblePanels = getVisiblePanels()
        guard !visiblePanels.isEmpty else {
            selectedPanel = .status
            return
        }

        guard let current = selectedPanel else {
            selectedPanel = visiblePanels.first
            return
        }

        let currentIndex: Int?
        if current == .balance || current == .balances {
            currentIndex = visiblePanels.firstIndex { $0 == .balance || $0 == .balances }
        } else {
            currentIndex = visiblePanels.firstIndex(of: current)
        }

        if let idx = currentIndex {
            let nextIndex = (idx + 1) % visiblePanels.count
            let nextPanel = visiblePanels[nextIndex]
            if nextPanel == .balance || nextPanel == .balances {
                selectedPanel = .balances
            } else {
                selectedPanel = nextPanel
            }
        } else {
            if let firstPanel = visiblePanels.first {
                if firstPanel == .balance || firstPanel == .balances {
                    selectedPanel = .balances
                } else {
                    selectedPanel = firstPanel
                }
            } else {
                selectedPanel = .status
            }
        }
    }

    public func getVisiblePanels() -> [PanelType] {
        let allPanels: [PanelType] = [.status, .balances, .activity, .price, .swap, .logs]
        return allPanels.filter { isVisible($0) }
    }

    private func ensureAtLeastOneVisible() {
        let visibleCount = visibility.values.filter { $0 }.count

        if visibleCount == 0 {
            visibility[.status] = true
            selectedPanel = .status
        } else if selectedPanel == nil || !isVisible(selectedPanel!) {
            if let firstVisible = getVisiblePanels().first {
                selectedPanel = firstVisible
            }
        }
    }

    private func saveConfig() async throws {
        let config = PanelToggleConfig(
            visibility: visibility,
            selectedPanel: selectedPanel
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(config)

        let configURL = URL(fileURLWithPath: configPath)
        let configDir = configURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: configDir.path) {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        try data.write(to: configURL)
    }

    private static func loadConfig(from path: String, fileManager: FileManager) -> PanelToggleConfig? {
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        guard let data = fileManager.contents(atPath: path) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(PanelToggleConfig.self, from: data)
        } catch {
            return nil
        }
    }
}

public enum PanelToggleError: Error, Sendable {
    case invalidPanelType
    case noVisiblePanels
}
