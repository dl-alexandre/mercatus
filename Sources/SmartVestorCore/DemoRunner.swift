import Foundation
import Utils

public func runRobinhoodMLDemo() async {
    let logger = StructuredLogger()
    let demo = RobinhoodMLDemo(logger: logger)

    do {
        try await demo.run()
    } catch {
        logger.error(
            component: "DemoRunner",
            event: "Demo failed",
            data: ["error": error.localizedDescription]
        )
        print("\n❌ Demo failed: \(error.localizedDescription)")
    }
}
