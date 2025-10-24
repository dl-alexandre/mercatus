import Foundation
import Utils
import Core
import Connectors

let logger = StructuredLogger()
let configurationManager = ConfigurationManager()

Task {
    do {
        let config = try configurationManager.load()

        let engine = LiveArbitrageEngine(
            config: config,
            logger: logger,
            configManager: configurationManager
        )

        logger.info(component: "Runtime", event: "engine_initializing")

        try await engine.start()

        while await engine.isRunning {
            try await Task.sleep(for: .seconds(1))
        }

    } catch {
        logger.error(
            component: "Runtime",
            event: "runtime_error",
            data: ["error": error.localizedDescription]
        )
        exit(EXIT_FAILURE)
    }
}

RunLoop.main.run()
