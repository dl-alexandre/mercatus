import Foundation
import Utils

public class ModelManager: ModelManagerProtocol {
    private var models: [String: ModelInfo] = [:]
    private var activeModels: [ModelInfo.ModelType: ModelInfo] = [:]
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func deployModel(_ modelInfo: ModelInfo, strategy: DeploymentStrategy) async throws {
        guard validateModel(modelInfo) else {
            throw ModelManagementError.invalidModel
        }

        switch strategy {
        case .immediate:
            try await deployImmediately(modelInfo)
        case .canary:
            try await deployCanary(modelInfo)
        case .shadow:
            try await deployShadow(modelInfo)
        }

        models[modelInfo.modelId] = modelInfo
        logger.info(component: "ModelManager", event: "Deployed model \(modelInfo.modelId) with strategy \(strategy.rawValue)")
    }

    public func rollbackModel(to version: String) async throws {
        guard let modelToRollback = models.values.first(where: { $0.version == version }) else {
            throw ModelManagementError.modelNotFound
        }

        activeModels[modelToRollback.modelType] = modelToRollback

        logger.info(component: "ModelManager", event: "Rolled back to model version \(version)")
    }

    public func getActiveModel(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return activeModels[modelType]
    }

    public func getAllModels() -> [ModelInfo] {
        return Array(models.values)
    }

    public func validateModel(_ modelInfo: ModelInfo) -> Bool {
        return modelInfo.accuracy > 0.0 &&
               modelInfo.accuracy <= 1.0 &&
               !modelInfo.modelId.isEmpty &&
               !modelInfo.version.isEmpty &&
               !modelInfo.trainingDataHash.isEmpty
    }

    public func archiveModel(_ modelId: String) async throws {
        guard let model = models[modelId] else {
            throw ModelManagementError.modelNotFound
        }

        var archivedModel = model
        archivedModel = ModelInfo(
            modelId: archivedModel.modelId,
            version: archivedModel.version,
            modelType: archivedModel.modelType,
            trainingDataHash: archivedModel.trainingDataHash,
            accuracy: archivedModel.accuracy,
            createdAt: archivedModel.createdAt,
            isActive: false
        )

        models[modelId] = archivedModel

        if activeModels[model.modelType]?.modelId == modelId {
            activeModels.removeValue(forKey: model.modelType)
        }

        logger.info(component: "ModelManager", event: "Archived model \(modelId)")
    }

    private func deployImmediately(_ modelInfo: ModelInfo) async throws {
        activeModels[modelInfo.modelType] = modelInfo
        logger.info(component: "ModelManager", event: "Deployed model \(modelInfo.modelId) immediately")
    }

    private func deployCanary(_ modelInfo: ModelInfo) async throws {
        activeModels[modelInfo.modelType] = modelInfo
        logger.info(component: "ModelManager", event: "Deployed model \(modelInfo.modelId) with canary strategy")
    }

    private func deployShadow(_ modelInfo: ModelInfo) async throws {
        logger.info(component: "ModelManager", event: "Deployed model \(modelInfo.modelId) in shadow mode")
    }
}

public enum ModelManagementError: Error {
    case invalidModel
    case modelNotFound
    case deploymentFailed
    case rollbackFailed
}
