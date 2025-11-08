import Foundation
import ArgumentParser
import SmartVestor
import Core

struct TUIGraphTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-graph",
        abstract: "Test graph rendering with different symbol modes for regression checks.",
        shouldDisplay: true
    )

    @Option(name: .shortAndLong, help: "Graph mode: all, braille, block, tty, ascii, default")
    var mode: String = "all"

    @Option(name: .shortAndLong, help: "Output format: stdout, snapshot")
    var output: String = "stdout"

    @Option(name: .shortAndLong, help: "Terminal width (default 80)")
    var width: Int = 80

    @Flag(name: .long, help: "Compare against stored snapshots")
    var compare: Bool = false

    mutating func run() async throws {
        let modesToTest: [GraphMode]
        if mode == "all" {
            modesToTest = [.braille, .block, .tty, .ascii, .default]
        } else {
            let normalizedMode = mode.lowercased()
            let graphMode: GraphMode?
            switch normalizedMode {
            case "braille":
                graphMode = .braille
            case "block":
                graphMode = .block
            case "tty":
                graphMode = .tty
            case "ascii":
                graphMode = .ascii
            case "default":
                graphMode = .default
            default:
                graphMode = GraphMode(rawValue: normalizedMode)
            }
            guard let selectedMode = graphMode else {
                print("Error: Invalid mode '\(mode)'. Valid modes: braille, block, tty, ascii, default")
                throw ExitCode.failure
            }
            modesToTest = [selectedMode]
        }

        let testCases: [(name: String, values: [Double])] = [
            ("empty", []),
            ("single", [5.0]),
            ("constant", Array(repeating: 5.0, count: 20)),
            ("increasing", (0..<20).map { Double($0) }),
            ("decreasing", (0..<20).reversed().map { Double($0) }),
            ("sine", (0..<20).map { sin(Double($0) * 0.5) }),
            ("spike", [1.0, 2.0, 3.0, 10.0, 3.0, 2.0, 1.0]),
            ("negative", (-10..<10).map { Double($0) }),
            ("large", (0..<20).map { Double($0) * 1000.0 })
        ]

        var snapshots: [String: [String]] = [:]

        for graphMode in modesToTest {
            print("\n=== Testing \(graphMode.rawValue) mode ===")

            let renderer = SparklineRenderer(
                unicodeSupported: true,
                graphMode: graphMode,
                scaler: AutoScaler()
            )

            for testCase in testCases {
                let sparkline = renderer.render(
                    values: testCase.values,
                    width: width,
                    minHeight: 1,
                    maxHeight: 4
                )

                let outputLine = "\(testCase.name.padding(toLength: 12, withPad: " ", startingAt: 0)): \(sparkline.isEmpty ? "(empty)" : sparkline)"
                print(outputLine)

                let key = "\(graphMode.rawValue)-\(testCase.name)"
                snapshots[key] = [outputLine]
            }
        }

        if output == "snapshot" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(snapshots),
               let json = String(data: data, encoding: .utf8) {
                print("\n=== Snapshot JSON ===")
                print(json)
            }
        }

        if compare {
            print("\n=== Comparison Mode ===")
            print("Note: Snapshot comparison requires stored reference files.")
            print("Store snapshots in tests/snapshots/graph_test.json for comparison.")
        }
    }
}
