import Testing
import ReinforcementLearning
import Utils
import Core
import MLX
import Foundation

@Suite("Reinforcement Learning Tests")
struct ReinforcementLearningTests {
    @Test("Mock Environment functionality")
    func testMockEnvironment() throws {
        let env = StochasticPriceEnvironment()
        let obs = env.reset()
        #expect(obs.count == 5)
        let (nextObs, _, done, _) = env.step(action: 0)
        #expect(nextObs.count == 5)
        #expect(!done)  // Should not be done immediately
    }

    @Test("Compute Advantages algorithm")
    func testComputeAdvantages() throws {
        let rewards: [Float] = [1.0, 2.0, 3.0]
        let values: [Float] = [0.5, 1.5, 2.5]
        let dones = [false, false, true]
        let advantages = computeAdvantages(rewards: rewards, values: values, dones: dones)
        #expect(advantages.count == 3)
    }

    @Test("Portfolio Environment functionality")
    func testPortfolioEnvironment() throws {
        // Mock historical data: 3 assets, 10 time steps
        let historicalData: [[Float]] = [
            [100.0, 200.0, 300.0],
            [101.0, 199.0, 305.0],
            [102.0, 201.0, 302.0],
            [103.0, 198.0, 308.0],
            [104.0, 202.0, 301.0],
            [105.0, 203.0, 299.0],
            [106.0, 197.0, 310.0],
            [107.0, 205.0, 298.0],
            [108.0, 196.0, 315.0],
            [109.0, 208.0, 297.0]
        ]

        let env = PortfolioEnvironment(historicalData: historicalData, transactionCost: 0.001)
        let obs = env.reset()
        #expect(obs.count == 6)  // 3 weights + 3 prices

        let (nextObs, reward, done, info) = env.step(action: 0)
        #expect(nextObs.count == 6)
        #expect(!done)
        #expect(reward.isFinite)
        #expect(info["portfolio_value"] as? Float ?? 0 > 0)
    }

    @Test("Policy Network initialization")
    func testPolicyNetwork() throws {
        autoreleasepool {
            let policy = PolicyNetwork(inputSize: 5, hiddenSize: 10, outputSize: 3)
            let input = MLXArray([1.0, 2.0, 3.0, 4.0, 5.0], [1, 5])
            let output = policy(input)
            #expect(output.shape == [1, 3])
        }
    }
}
