// ReinforcementLearning module for MLX Swift
// Implements PPO (Proximal Policy Optimization) for reinforcement learning

import Foundation
import MLX
import MLXNN
import MLXOptimizers
import Utils

public protocol Environment {
    func reset() -> [Float]
    func step(action: Int) -> (observation: [Float], reward: Float, done: Bool, info: [String: Any])
    var actionSpaceSize: Int { get }
    var observationSpaceSize: Int { get }
}

public class PolicyNetwork: Module {
    @ModuleInfo var linear1: Linear
    @ModuleInfo var linear2: Linear
    @ModuleInfo var linear3: Linear

    public init(inputSize: Int, hiddenSize: Int, outputSize: Int) {
        self.linear1 = Linear(inputSize, hiddenSize)
        self.linear2 = Linear(hiddenSize, hiddenSize)
        self.linear3 = Linear(hiddenSize, outputSize)
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let x1 = relu(linear1(x))
        let x2 = relu(linear2(x1))
        return linear3(x2)
    }
}

public class ValueNetwork: Module {
    @ModuleInfo var linear1: Linear
    @ModuleInfo var linear2: Linear
    @ModuleInfo var linear3: Linear

    public init(inputSize: Int, hiddenSize: Int, outputSize: Int = 1) {
        self.linear1 = Linear(inputSize, hiddenSize)
        self.linear2 = Linear(hiddenSize, hiddenSize)
        self.linear3 = Linear(hiddenSize, outputSize)
        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let x1 = relu(linear1(x))
        let x2 = relu(linear2(x1))
        return linear3(x2)
    }
}

public func computeAdvantages(rewards: [Float], values: [Float], dones: [Bool], gamma: Float = 0.99, lambda: Float = 0.95) -> [Float] {
    let n = rewards.count
    var advantages = [Float](repeating: 0.0, count: n)
    var lastAdvantage: Float = 0.0

    for t in (0..<n).reversed() {
        if dones[t] {
            advantages[t] = rewards[t] - values[t]
            lastAdvantage = 0.0
        } else {
            let delta = rewards[t] + gamma * (t + 1 < values.count ? values[t + 1] : 0.0) - values[t]
            advantages[t] = delta + gamma * lambda * lastAdvantage
            lastAdvantage = advantages[t]
        }
    }

    return advantages
}

public func ppoUpdate(policy: PolicyNetwork, value: ValueNetwork, optimizer: Optimizer, observations: [[Float]], actions: [Int], oldLogProbs: [Float], advantages: [Float], returns: [Float], clipEpsilon: Float = 0.2, valueCoef: Float = 0.5, entropyCoef: Float = 0.01) -> (policyLoss: Float, valueLoss: Float) {
    let obsArray = MLXArray(observations.flatMap { $0 }, [observations.count, observations[0].count])
    let actionArray = MLXArray(actions.map(Float.init))
    let oldLogProbArray = MLXArray(oldLogProbs)
    let advantageArray = MLXArray(advantages)
    let returnArray = MLXArray(returns)

    // Policy update
    let policyLossFn: (PolicyNetwork, MLXArray, MLXArray) -> MLXArray = { model, _, _ in
        let logits = model(obsArray)
        let newLogProbs = log(softmax(logits, axis: 1))
        let actionLogProbs = newLogProbs[0..., actionArray]

        let ratio = exp(actionLogProbs - oldLogProbArray)
        let clipMin = MLXArray(1 - clipEpsilon)
        let clipMax = MLXArray(1 + clipEpsilon)
        let clippedRatio = MLX.minimum(MLX.maximum(ratio, clipMin), clipMax)
        let policyLoss = -MLX.minimum(ratio * advantageArray, clippedRatio * advantageArray).mean()

        let entropy = -sum(softmax(logits, axis: 1) * log(softmax(logits, axis: 1)), axis: 1).mean()
        return policyLoss - entropyCoef * entropy
    }

    let policyGradFn = valueAndGrad(model: policy, policyLossFn)
    let (policyLossValue, policyGrads) = policyGradFn(policy, obsArray, obsArray)
    optimizer.update(model: policy, gradients: policyGrads)

    // Value update
    let valueLossFn: (ValueNetwork, MLXArray, MLXArray) -> MLXArray = { model, _, _ in
        let values = model(obsArray).flattened()
        return pow(values - returnArray, 2).mean()
    }

    let valueGradFn = valueAndGrad(model: value, valueLossFn)
    let (valueLossValue, valueGrads) = valueGradFn(value, obsArray, obsArray)
    optimizer.update(model: value, gradients: valueGrads)

    return (policyLossValue.item(Float.self), valueLossValue.item(Float.self))
}

public class PPOAgent {
    private let policy: PolicyNetwork
    private let value: ValueNetwork
    private let optimizer: Adam
    private let logger: StructuredLogger

    public init(observationSize: Int, actionSize: Int, hiddenSize: Int = 128, learningRate: Float = 3e-4, logger: StructuredLogger) {
        self.policy = PolicyNetwork(inputSize: observationSize, hiddenSize: hiddenSize, outputSize: actionSize)
        self.value = ValueNetwork(inputSize: observationSize, hiddenSize: hiddenSize)
        self.optimizer = Adam(learningRate: learningRate)
        self.logger = logger
    }

    public func getAction(observation: [Float]) -> (action: Int, logProb: Float) {
        let obsArray = MLXArray(observation, [1, observation.count])
        let logits = policy(obsArray)
        let probs = softmax(logits, axis: 1)
        // For simplicity, use argmax; in full RL, use categorical sampling
        let probValues = probs[0].asArray(Float.self)
        var maxProb = probValues[0]
        var action = 0
        for i in 1..<probValues.count {
            if probValues[i] > maxProb {
                maxProb = probValues[i]
                action = i
            }
        }
        let logProb = log(MLXArray(maxProb)).item(Float.self)
        return (action, logProb)
    }

    public func train(env: Environment, numEpisodes: Int = 1000, maxSteps: Int = 1000) async {
        logger.info(component: "PPOAgent", event: "Starting training", data: ["episodes": String(numEpisodes), "maxSteps": String(maxSteps)])

        for episode in 0..<numEpisodes {
            var obs = env.reset()
            var episodeRewards: [Float] = []
            var episodeObservations: [[Float]] = [obs]
            var episodeActions: [Int] = []
            var episodeLogProbs: [Float] = []
            var episodeValues: [Float] = []
            var episodeDones: [Bool] = [false]

            for _ in 0..<maxSteps {
                let (action, logProb) = getAction(observation: obs)
                let value = value(MLXArray(obs, [1, obs.count])).item(Float.self)
                let (nextObs, reward, done, _) = env.step(action: action)

                episodeActions.append(action)
                episodeLogProbs.append(logProb)
                episodeValues.append(value)
                episodeRewards.append(reward)
                episodeDones.append(done)
                episodeObservations.append(nextObs)

                obs = nextObs
                if done { break }
            }

            // Compute advantages and returns
            let advantages = computeAdvantages(rewards: episodeRewards, values: episodeValues, dones: episodeDones)
            let returns = zip(advantages, episodeValues).map { $0.0 + $0.1 }

            // Update
            let (policyLoss, valueLoss) = ppoUpdate(
                policy: policy,
                value: value,
                optimizer: optimizer,
                observations: episodeObservations.dropLast(),
                actions: episodeActions,
                oldLogProbs: episodeLogProbs,
                advantages: advantages,
                returns: returns
            )

            if episode % 100 == 0 {
                let avgReward = episodeRewards.reduce(0, +) / Float(episodeRewards.count)
                logger.info(component: "PPOAgent", event: "Training progress", data: [
                    "episode": String(episode),
                    "avgReward": String(avgReward),
                    "policyLoss": String(policyLoss),
                    "valueLoss": String(valueLoss)
                ])
            }
        }

        logger.info(component: "PPOAgent", event: "Training completed")
    }
}
