import Foundation
import Utils

public struct ModelVersion: Codable, Equatable {
    public let version: String
    public let modelId: String
    public let modelType: String
    public let createdAt: Date
    public let metadata: [String: String]
    public let filePath: String
    public let checksum: String

    public init(version: String, modelId: String, modelType: String, createdAt: Date = Date(), metadata: [String: String] = [:], filePath: String, checksum: String) {
        self.version = version
        self.modelId = modelId
        self.modelType = modelType
        self.createdAt = createdAt
        self.metadata = metadata
        self.filePath = filePath
        self.checksum = checksum
    }
}

public struct ModelMetadata: Codable {
    public let architecture: String
    public let inputSize: Int
    public let outputSize: Int
    public let trainingEpochs: Int
    public let finalLoss: Double
    public let validationLoss: Double?
    public let accuracy: Double?
    public let hyperparameters: [String: String]

    public init(architecture: String, inputSize: Int, outputSize: Int, trainingEpochs: Int, finalLoss: Double, validationLoss: Double? = nil, accuracy: Double? = nil, hyperparameters: [String: String] = [:]) {
        self.architecture = architecture
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.trainingEpochs = trainingEpochs
        self.finalLoss = finalLoss
        self.validationLoss = validationLoss
        self.accuracy = accuracy
        self.hyperparameters = hyperparameters
    }
}

public class ModelRegistry {
    private let registryPath: String
    private let logger: StructuredLogger
    private var versions: [String: [ModelVersion]] = [:]

    public init(registryPath: String, logger: StructuredLogger) {
        self.registryPath = registryPath
        self.logger = logger

        if !FileManager.default.fileExists(atPath: registryPath) {
            try? FileManager.default.createDirectory(atPath: registryPath, withIntermediateDirectories: true)
        }

        loadRegistry()
    }

    public func register(model: MLXPricePredictionModel, modelId: String, version: String, metadata: ModelMetadata) throws -> ModelVersion {
        let fileName = "\(modelId)_v\(version).safetensors"
        let filePath = (registryPath as NSString).appendingPathComponent(fileName)

        try model.save(to: filePath)

        let checksum = try calculateChecksum(filePath: filePath)

        let modelVersion = ModelVersion(
            version: version,
            modelId: modelId,
            modelType: "MLXPricePredictionModel",
            createdAt: Date(),
            metadata: [
                "architecture": metadata.architecture,
                "inputSize": String(metadata.inputSize),
                "outputSize": String(metadata.outputSize),
                "trainingEpochs": String(metadata.trainingEpochs),
                "finalLoss": String(metadata.finalLoss),
                "validationLoss": metadata.validationLoss.map { String($0) } ?? "",
                "accuracy": metadata.accuracy.map { String($0) } ?? ""
            ],
            filePath: filePath,
            checksum: checksum
        )

        if versions[modelId] == nil {
            versions[modelId] = []
        }
        versions[modelId]?.append(modelVersion)

        saveRegistry()

        logger.info(component: "ModelRegistry", event: "Model registered", data: [
            "modelId": modelId,
            "version": version,
            "filePath": filePath
        ])

        return modelVersion
    }

    public func getLatestVersion(modelId: String) -> ModelVersion? {
        return versions[modelId]?.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    public func getVersion(modelId: String, version: String) -> ModelVersion? {
        return versions[modelId]?.first { $0.version == version }
    }

    public func listVersions(modelId: String) -> [ModelVersion] {
        return versions[modelId]?.sorted(by: { $0.createdAt > $1.createdAt }) ?? []
    }

    public func loadModel(modelId: String, version: String? = nil, logger: StructuredLogger) throws -> MLXPricePredictionModel? {
        let modelVersion: ModelVersion?
        if let version = version {
            modelVersion = getVersion(modelId: modelId, version: version)
        } else {
            modelVersion = getLatestVersion(modelId: modelId)
        }

        guard let version = modelVersion else {
            throw ModelRegistryError.modelNotFound(modelId: modelId, version: version)
        }

        let checksum = try calculateChecksum(filePath: version.filePath)
        guard checksum == version.checksum else {
            throw ModelRegistryError.checksumMismatch(expected: version.checksum, actual: checksum)
        }

        return try MLXPricePredictionModel.load(from: version.filePath, logger: logger)
    }

    public func deleteVersion(modelId: String, version: String) throws {
        guard let modelVersion = getVersion(modelId: modelId, version: version) else {
            throw ModelRegistryError.modelNotFound(modelId: modelId, version: version)
        }

        try FileManager.default.removeItem(atPath: modelVersion.filePath)
        versions[modelId]?.removeAll { $0.version == version }

        if versions[modelId]?.isEmpty == true {
            versions.removeValue(forKey: modelId)
        }

        saveRegistry()

        logger.info(component: "ModelRegistry", event: "Model version deleted", data: [
            "modelId": modelId,
            "version": version
        ])
    }

    public func deleteModels(for coinSymbol: String) throws {
        let modelIdPrefix = "\(coinSymbol.lowercased())_price_prediction"
        let matchingModelIds = versions.keys.filter { $0.hasPrefix(modelIdPrefix) }

        for modelId in matchingModelIds {
            if let modelVersions = versions[modelId] {
                for version in modelVersions {
                    try? FileManager.default.removeItem(atPath: version.filePath)
                }
            }
            versions.removeValue(forKey: modelId)
        }

        saveRegistry()

        logger.info(component: "ModelRegistry", event: "Deleted all models for coin", data: [
            "coinSymbol": coinSymbol,
            "deletedCount": String(matchingModelIds.count)
        ])
    }

    public func listModels(for coinSymbol: String) -> [ModelVersion] {
        let modelIdPrefix = "\(coinSymbol.lowercased())_price_prediction"
        var allVersions: [ModelVersion] = []

        for (modelId, modelVersions) in versions where modelId.hasPrefix(modelIdPrefix) {
            allVersions.append(contentsOf: modelVersions)
        }

        return allVersions.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private func calculateChecksum(filePath: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let hash = data.withUnsafeBytes { bytes in
            var hash = 0
            for byte in bytes {
                hash = ((hash << 5) &- hash) &+ Int(byte)
                hash = hash & hash
            }
            return abs(hash)
        }
        return String(hash)
    }

    private func saveRegistry() {
        let registryFile = (registryPath as NSString).appendingPathComponent("registry.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(versions) {
            try? data.write(to: URL(fileURLWithPath: registryFile))
        }
    }

    private func loadRegistry() {
        let registryFile = (registryPath as NSString).appendingPathComponent("registry.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: registryFile)) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let loaded = try? decoder.decode([String: [ModelVersion]].self, from: data) {
            versions = loaded
        }
    }
}

public enum ModelRegistryError: Error {
    case modelNotFound(modelId: String, version: String?)
    case checksumMismatch(expected: String, actual: String)

    public var localizedDescription: String {
        switch self {
        case .modelNotFound(let modelId, let version):
            return "Model not found: \(modelId) version \(version ?? "latest")"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        }
    }
}
