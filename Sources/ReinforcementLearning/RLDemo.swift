// Simple demo to show RL working
import Utils
import Foundation

public func runRLDemo() async {
    print("Starting RL Demo...")

    let logger = StructuredLogger()
    let env = StochasticPriceEnvironment()
    let agent = PPOAgent(observationSize: env.observationSpaceSize, actionSize: env.actionSpaceSize, logger: logger)

    print("Training RL agent for 10 episodes...")
    await agent.train(env: env, numEpisodes: 10, maxSteps: 50)

    print("RL Demo completed!")
}
