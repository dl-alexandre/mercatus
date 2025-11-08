import Foundation

public struct CommandBarItem: Sendable {
    public let label: String
    public let hotkey: String
    public let embedHotkey: Bool
    public let hotkeyPosition: Int?

    public init(label: String, hotkey: String, embedHotkey: Bool = false, hotkeyPosition: Int? = nil) {
        self.label = label
        self.hotkey = hotkey
        self.embedHotkey = embedHotkey
        self.hotkeyPosition = hotkeyPosition
    }
}

public final class CommandBarRenderer: @unchecked Sendable {
    private let colorManager: ColorManagerProtocol
    private let separator: String

    public init(colorManager: ColorManagerProtocol = ColorManager(), separator: String = "  ") {
        self.colorManager = colorManager
        self.separator = separator
    }

    public func render(items: [CommandBarItem], highlightedKey: String? = nil) -> String {
        guard !items.isEmpty else {
            return ""
        }

        let formattedItems = items.map { item in
        let isHighlighted = highlightedKey?.lowercased() == item.hotkey.lowercased()

        if item.embedHotkey, let position = item.hotkeyPosition {
            // For embedded hotkeys, insert the hotkey in brackets at the specified position
            let hotkeyPart = "[\(item.hotkey)]"
        let formattedHotkey: String
        if isHighlighted {
                let boldHotkey = colorManager.bold(hotkeyPart)
            formattedHotkey = "\u{001B}[7m\(boldHotkey)\u{001B}[27m"
            } else {
                formattedHotkey = colorManager.bold(hotkeyPart)
            }

                // Insert the formatted hotkey at the specified position
                let prefix = String(item.label.prefix(position))
                let suffix = String(item.label.dropFirst(position))
                return "\(prefix)\(formattedHotkey)\(suffix)"
            } else {
                // Default behavior: hotkey in brackets at the beginning
                let hotkeyPart = "[\(item.hotkey)]"
                let formattedHotkey: String
                if isHighlighted {
                    let boldHotkey = colorManager.bold(hotkeyPart)
                    formattedHotkey = "\u{001B}[7m\(boldHotkey)\u{001B}[27m"
                } else {
                    formattedHotkey = colorManager.bold(hotkeyPart)
                }

                return "\(formattedHotkey)\(item.label)"
            }
        }

        return formattedItems.joined(separator: separator)
    }

    public func renderDefaultCommands(isRunning: Bool = true, highlightedKey: String? = nil) -> String {
        var commands: [CommandBarItem] = []

        if isRunning {
            commands.append(CommandBarItem(label: "ause", hotkey: "P"))
        } else {
            commands.append(CommandBarItem(label: "tart", hotkey: "S"))
        }
        commands.append(CommandBarItem(label: "esume", hotkey: "R"))
        commands.append(CommandBarItem(label: "refresh", hotkey: "F", embedHotkey: true, hotkeyPosition: 2))
        commands.append(CommandBarItem(label: "elp", hotkey: "H"))
        commands.append(CommandBarItem(label: "ogs", hotkey: "L"))
        commands.append(CommandBarItem(label: "uit", hotkey: "Q"))

        return render(items: commands, highlightedKey: highlightedKey)
    }

    public func renderContextSensitiveCommands(for panelType: PanelType?, isRunning: Bool = true, highlightedKey: String? = nil) -> String {
        let commands = Self.getCommands(for: panelType, isRunning: isRunning)
        return render(items: commands, highlightedKey: highlightedKey)
    }

    public func renderPanelTabs(visiblePanels: [PanelType], selectedPanel: PanelType?, colorManager: ColorManagerProtocol) -> String {
        let panelNames: [PanelType: String] = [
            .status: "Status",
            .balances: "Balances",
            .balance: "Balances",
            .activity: "Activity",
            .price: "Prices",
            .swap: "Swaps",
            .logs: "Logs"
        ]

        let uniquePanels = Array(Set(visiblePanels.map { $0 == .balance ? PanelType.balances : $0 }))
        let orderedPanels = [PanelType.status, .balances, .activity, .price, .swap, .logs].filter { uniquePanels.contains($0) }

        let tabs = orderedPanels.map { panelType in
            let name = panelNames[panelType] ?? panelType.rawValue.capitalized
            let isSelected = selectedPanel == panelType ||
                           (panelType == .balance && selectedPanel == .balances) ||
                           (panelType == .balances && selectedPanel == .balance)

            if isSelected {
                return colorManager.bold("\u{001B}[7m \(name) \u{001B}[27m")
            } else {
                return " \(name) "
            }
        }

        return tabs.joined(separator: "│")
    }

    private static func getCommands(for panelType: PanelType?, isRunning: Bool) -> [CommandBarItem] {
        guard let panelType = panelType else {
            return getCommands(for: .status, isRunning: isRunning)
        }

        switch panelType {
        case .status:
            var items: [CommandBarItem] = []
            if isRunning {
                items.append(CommandBarItem(label: "ause", hotkey: "P"))
            } else {
                items.append(CommandBarItem(label: "tart", hotkey: "S"))
            }
            items.append(CommandBarItem(label: "esume", hotkey: "R"))
            items.append(CommandBarItem(label: "elp", hotkey: "H"))
            items.append(CommandBarItem(label: "uit", hotkey: "Q"))
            return items

        case .balances, .balance:
            return [
                CommandBarItem(label: "↓", hotkey: "J"),
                CommandBarItem(label: "↑", hotkey: "K"),
                CommandBarItem(label: "PgDn", hotkey: "Ctrl+J"),
                CommandBarItem(label: "PgUp", hotkey: "Ctrl+K"),
                CommandBarItem(label: "elp", hotkey: "H"),
                CommandBarItem(label: "uit", hotkey: "Q")
            ]

        case .activity:
            return [
                CommandBarItem(label: "↓", hotkey: "J"),
                CommandBarItem(label: "↑", hotkey: "K"),
                CommandBarItem(label: "PgDn", hotkey: "Ctrl+J"),
                CommandBarItem(label: "PgUp", hotkey: "Ctrl+K"),
                CommandBarItem(label: "elp", hotkey: "H"),
                CommandBarItem(label: "uit", hotkey: "Q")
            ]

        case .price:
            return [
                CommandBarItem(label: "↓", hotkey: "J"),
                CommandBarItem(label: "↑", hotkey: "K"),
                CommandBarItem(label: "PgDn", hotkey: "Ctrl+J"),
                CommandBarItem(label: "PgUp", hotkey: "Ctrl+K"),
                CommandBarItem(label: "rder", hotkey: "O"),
                CommandBarItem(label: "elp", hotkey: "H"),
                CommandBarItem(label: "uit", hotkey: "Q")
            ]

        case .swap:
            return [
                CommandBarItem(label: "↓", hotkey: "J"),
                CommandBarItem(label: "↑", hotkey: "K"),
                CommandBarItem(label: "PgDn", hotkey: "Ctrl+J"),
                CommandBarItem(label: "PgUp", hotkey: "Ctrl+K"),
                CommandBarItem(label: "xecute", hotkey: "E"),
                CommandBarItem(label: "elp", hotkey: "H"),
                CommandBarItem(label: "uit", hotkey: "Q")
            ]

        default:
            return [
                CommandBarItem(label: "elp", hotkey: "H"),
                CommandBarItem(label: "uit", hotkey: "Q")
            ]
        }
    }
}
