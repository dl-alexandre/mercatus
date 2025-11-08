import Foundation
import Utils

public struct FederatedClientUpdate {
    public let clientId: String
    public let weights: [String: [Float]]
    public let sampleCount: Int
    public let timestamp: Date

    public init(clientId: String, weights: [String: [Float]], sampleCount: Int, timestamp: Date = Date()) {
        self.clientId = clientId
        self.weights = weights
        self.sampleCount = sampleCount
        self.timestamp = timestamp
    }
}

public struct FederatedServerConfig {
    public let numRounds: Int
    public let clientsPerRound: Int
    public let learningRate: Float
    public let privacyBudget: Double

    public init(numRounds: Int = 10, clientsPerRound: Int = 5, learningRate: Float = 0.01, privacyBudget: Double = 1.0) {
        self.numRounds = numRounds
        self.clientsPerRound = clientsPerRound
        self.learningRate = learningRate
        self.privacyBudget = privacyBudget
    }
}

public class FederatedLearningServer {
    private let logger: StructuredLogger
    private var globalWeights: [String: [Float]] = [:]
    private var clientUpdates: [FederatedClientUpdate] = []

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func aggregateUpdates(updates: [FederatedClientUpdate]) -> [String: [Float]] {
        guard !updates.isEmpty else { return globalWeights }

        var aggregated: [String: [Float]] = [:]
        let totalSamples = updates.map { $0.sampleCount }.reduce(0, +)

        for update in updates {
            let weight = Float(update.sampleCount) / Float(totalSamples)

            for (key, values) in update.weights {
                if aggregated[key] == nil {
                    aggregated[key] = Array(repeating: 0.0, count: values.count)
                }

                for i in 0..<values.count {
                    aggregated[key]![i] += values[i] * weight
                }
            }
        }

        logger.info(component: "FederatedLearningServer", event: "Updates aggregated", data: [
            "numClients": String(updates.count),
            "totalSamples": String(totalSamples)
        ])

        return aggregated
    }

    public func addDifferentialPrivacy(weights: [String: [Float]], noiseScale: Double) -> [String: [Float]] {
        var noisyWeights = weights

        for (key, values) in noisyWeights {
            let noise = (0..<values.count).map { _ in
                Float.random(in: Float(-noiseScale)...Float(noiseScale))
            }
            noisyWeights[key] = zip(values, noise).map { $0.0 + $0.1 }
        }

        logger.info(component: "FederatedLearningServer", event: "Differential privacy applied", data: [
            "noiseScale": String(noiseScale)
        ])

        return noisyWeights
    }

    public func federatedRound(updates: [FederatedClientUpdate], config: FederatedServerConfig) -> [String: [Float]] {
        let aggregated = aggregateUpdates(updates: updates)
        let privacyBudget = config.privacyBudget / Double(config.numRounds)
        let noisyWeights = addDifferentialPrivacy(weights: aggregated, noiseScale: privacyBudget)

        globalWeights = noisyWeights
        clientUpdates.append(contentsOf: updates)

        return globalWeights
    }
}

public class FederatedLearningClient {
    private let clientId: String
    private let logger: StructuredLogger

    public init(clientId: String, logger: StructuredLogger) {
        self.clientId = clientId
        self.logger = logger
    }

    public func trainLocal(data: [[Double]], targets: [[Double]], epochs: Int = 5) -> FederatedClientUpdate {
        logger.info(component: "FederatedLearningClient", event: "Local training started", data: [
            "clientId": clientId,
            "samples": String(data.count)
        ])

        let weights: [String: [Float]] = [
            "layer1": Array(repeating: Float.random(in: -0.1...0.1), count: 100),
            "layer2": Array(repeating: Float.random(in: -0.1...0.1), count: 50)
        ]

        return FederatedClientUpdate(
            clientId: clientId,
            weights: weights,
            sampleCount: data.count
        )
    }
}
