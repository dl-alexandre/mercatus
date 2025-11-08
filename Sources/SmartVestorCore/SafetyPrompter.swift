import Foundation
import Utils

public struct SafetyPrompter {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger = StructuredLogger()) {
        self.logger = logger
    }

    public func confirmProductionMode(config: SmartVestorConfig) -> Bool {
        print("\n╔═══════════════════════════════════════════════════════════╗")
        print("║           ⚠️  PRODUCTION MODE WARNING                    ║")
        print("╚═══════════════════════════════════════════════════════════╝")
        print("")
        print("You are about to enable PRODUCTION MODE.")
        print("")
        print("This will:")
        print("  • Execute REAL trades with REAL money")
        print("  • Place orders on connected exchanges")
        print("  • Update your actual portfolio balances")
        print("")
        print("Current Configuration:")
        print("  • Deposit Amount: $\(String(format: "%.2f", config.depositAmount))")
        print("  • Fee Cap: \(String(format: "%.3f%%", config.feeCap * 100))")
        print("  • RSI Threshold: \(String(format: "%.1f", config.rsiThreshold))")
        print("  • Price Threshold: \(String(format: "%.2f", config.priceThreshold))")
        print("  • Simulation Mode: \(config.simulation.enabled ? "ENABLED (will be disabled)" : "DISABLED")")
        print("")
        print("Safety Checks:")
        print("  • Spread analysis: ACTIVE")
        print("  • Market condition monitoring: ACTIVE")
        print("  • Risk limits: ACTIVE")
        print("")
        print("═══════════════════════════════════════════════════════════")
        print("Type 'YES' (all caps) to confirm production mode:")
        print("═══════════════════════════════════════════════════════════")
        print("> ", terminator: "")

        guard let response = readLine() else {
            logger.warn(component: "SafetyPrompter", event: "No input received for production confirmation")
            return false
        }

        let confirmed = response.trimmingCharacters(in: .whitespacesAndNewlines) == "YES"

        if confirmed {
            logger.info(component: "SafetyPrompter", event: "Production mode confirmed by user")
            print("")
            print("✅ Production mode confirmed. Starting automation...")
            print("")
        } else {
            logger.warn(component: "SafetyPrompter", event: "Production mode not confirmed", data: [
                "response": response
            ])
            print("")
            print("❌ Production mode not confirmed. Exiting.")
            print("")
        }

        return confirmed
    }
}
