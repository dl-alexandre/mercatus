import Foundation
import Utils

public protocol RetrainingPipelineProtocol {
    func startScheduledRetraining() async throws
    func stopScheduledRetraining() async throws
    func triggerImmediateRetraining(modelType: ModelInfo.ModelType) async throws
    func getRetrainingStatus() -> RetrainingStatus
    func configureRetrainingSchedule(_ schedule: RetrainingSchedule) async throws
}

public struct RetrainingSchedule: Sendable {
    public let modelTypes: [ModelInfo.ModelType]
    public let frequency: RetrainingFrequency
    public let timeWindow: TimeWindow
    public let performanceThreshold: Double
    public let dataThreshold: Int
    public let enabled: Bool

    public init(modelTypes: [ModelInfo.ModelType], frequency: RetrainingFrequency, timeWindow: TimeWindow, performanceThreshold: Double, dataThreshold: Int, enabled: Bool) {
        self.modelTypes = modelTypes
        self.frequency = frequency
        self.timeWindow = timeWindow
        self.performanceThreshold = performanceThreshold
        self.dataThreshold = dataThreshold
        self.enabled = enabled
    }
}

public enum RetrainingFrequency: String, CaseIterable, Sendable {
    case hourly = "HOURLY"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case onDemand = "ON_DEMAND"
}

public struct TimeWindow: Sendable {
    public let startHour: Int
    public let endHour: Int
    public let timezone: String

    public init(startHour: Int, endHour: Int, timezone: String) {
        self.startHour = startHour
        self.endHour = endHour
        self.timezone = timezone
    }
}

public struct RetrainingStatus {
    public let isRunning: Bool
    public let lastRetraining: Date?
    public let nextScheduledRetraining: Date?
    public let activeJobs: [RetrainingJob]
    public let totalRetrainings: Int
    public let successfulRetrainings: Int
    public let failedRetrainings: Int

    public init(isRunning: Bool, lastRetraining: Date?, nextScheduledRetraining: Date?, activeJobs: [RetrainingJob], totalRetrainings: Int, successfulRetrainings: Int, failedRetrainings: Int) {
        self.isRunning = isRunning
        self.lastRetraining = lastRetraining
        self.nextScheduledRetraining = nextScheduledRetraining
        self.activeJobs = activeJobs
        self.totalRetrainings = totalRetrainings
        self.successfulRetrainings = successfulRetrainings
        self.failedRetrainings = failedRetrainings
    }
}

public struct RetrainingJob {
    public let jobId: String
    public let modelType: ModelInfo.ModelType
    public let status: JobStatus
    public let startedAt: Date
    public let completedAt: Date?
    public let progress: Double
    public let error: String?

    public init(jobId: String, modelType: ModelInfo.ModelType, status: JobStatus, startedAt: Date, completedAt: Date?, progress: Double, error: String?) {
        self.jobId = jobId
        self.modelType = modelType
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.progress = progress
        self.error = error
    }
}

public enum JobStatus: String, CaseIterable {
    case pending = "PENDING"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

public final class RetrainingPipeline: RetrainingPipelineProtocol, @unchecked Sendable {
    private let dataIngestionService: DataIngestionProtocol
    private let bootstrapTrainer: BootstrapTrainingProtocol
    private let modelManager: ModelManagerProtocol
    private let driftDetector: DriftDetectionProtocol
    private let performanceMonitor: PerformanceMonitoringProtocol
    private let logger: StructuredLogger

    private var isRunning = false
    private var retrainingTask: Task<Void, Never>?
    private var currentSchedule: RetrainingSchedule?
    private var activeJobs: [String: RetrainingJob] = [:]
    private var retrainingStats = RetrainingStats()

    public init(
        dataIngestionService: DataIngestionProtocol,
        bootstrapTrainer: BootstrapTrainingProtocol,
        modelManager: ModelManagerProtocol,
        driftDetector: DriftDetectionProtocol,
        performanceMonitor: PerformanceMonitoringProtocol,
        logger: StructuredLogger
    ) {
        self.dataIngestionService = dataIngestionService
        self.bootstrapTrainer = bootstrapTrainer
        self.modelManager = modelManager
        self.driftDetector = driftDetector
        self.performanceMonitor = performanceMonitor
        self.logger = logger
    }

    public func startScheduledRetraining() async throws {
        guard !isRunning else {
            logger.warn(component: "RetrainingPipeline", event: "Retraining pipeline is already running")
            return
        }

        guard let schedule = currentSchedule, schedule.enabled else {
            throw RetrainingError.noScheduleConfigured
        }

        isRunning = true
        logger.info(component: "RetrainingPipeline", event: "Starting scheduled retraining pipeline")

        let scheduleCopy = schedule
        retrainingTask = Task { @Sendable in
            await self.runRetrainingLoop(schedule: scheduleCopy)
        }
    }

    public func stopScheduledRetraining() async throws {
        guard isRunning else {
            logger.warn(component: "RetrainingPipeline", event: "Retraining pipeline is not running")
            return
        }

        isRunning = false
        retrainingTask?.cancel()
        retrainingTask = nil

        logger.info(component: "RetrainingPipeline", event: "Stopped scheduled retraining pipeline")
    }

    public func triggerImmediateRetraining(modelType: ModelInfo.ModelType) async throws {
        let jobId = UUID().uuidString
        logger.info(component: "RetrainingPipeline", event: "Triggering immediate retraining", data: [
            "jobId": jobId,
            "modelType": modelType.rawValue
        ])

        let job = RetrainingJob(
            jobId: jobId,
            modelType: modelType,
            status: .pending,
            startedAt: Date(),
            completedAt: nil,
            progress: 0.0,
            error: nil
        )

        activeJobs[jobId] = job

        let jobIdCopy = jobId
        let modelTypeCopy = modelType
        Task { @Sendable in
            await self.executeRetrainingJob(jobId: jobIdCopy, modelType: modelTypeCopy)
        }
    }

    public func getRetrainingStatus() -> RetrainingStatus {
        return RetrainingStatus(
            isRunning: isRunning,
            lastRetraining: retrainingStats.lastRetraining,
            nextScheduledRetraining: calculateNextRetraining(),
            activeJobs: Array(activeJobs.values),
            totalRetrainings: retrainingStats.totalRetrainings,
            successfulRetrainings: retrainingStats.successfulRetrainings,
            failedRetrainings: retrainingStats.failedRetrainings
        )
    }

    public func configureRetrainingSchedule(_ schedule: RetrainingSchedule) async throws {
        currentSchedule = schedule
        logger.info(component: "RetrainingPipeline", event: "Configured retraining schedule", data: [
            "frequency": schedule.frequency.rawValue,
            "modelTypes": schedule.modelTypes.map { $0.rawValue }.joined(separator: ","),
            "enabled": String(schedule.enabled)
        ])
    }

    private func runRetrainingLoop(schedule: RetrainingSchedule) async {
        while isRunning {
            do {
                if shouldRetrain(schedule: schedule) {
                    for modelType in schedule.modelTypes {
                        try await triggerImmediateRetraining(modelType: modelType)
                    }
                }

                let sleepInterval = calculateSleepInterval(frequency: schedule.frequency)
                try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
            } catch {
                logger.error(component: "RetrainingPipeline", event: "Error in retraining loop: \(error)")
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Sleep 1 minute on error
            }
        }
    }

    private func shouldRetrain(schedule: RetrainingSchedule) -> Bool {
        guard let lastRetraining = retrainingStats.lastRetraining else {
            return true
        }

        let timeSinceLastRetraining = Date().timeIntervalSince(lastRetraining)
        let requiredInterval = getRequiredInterval(frequency: schedule.frequency)

        return timeSinceLastRetraining >= requiredInterval
    }

    private func getRequiredInterval(frequency: RetrainingFrequency) -> TimeInterval {
        switch frequency {
        case .hourly:
            return 3600 // 1 hour
        case .daily:
            return 86400 // 24 hours
        case .weekly:
            return 604800 // 7 days
        case .monthly:
            return 2592000 // 30 days
        case .onDemand:
            return Double.infinity
        }
    }

    private func calculateSleepInterval(frequency: RetrainingFrequency) -> TimeInterval {
        switch frequency {
        case .hourly:
            return 300 // Check every 5 minutes
        case .daily:
            return 3600 // Check every hour
        case .weekly:
            return 21600 // Check every 6 hours
        case .monthly:
            return 86400 // Check daily
        case .onDemand:
            return 3600 // Check hourly
        }
    }

    private func calculateNextRetraining() -> Date? {
        guard let schedule = currentSchedule, schedule.enabled else {
            return nil
        }

        let lastRetraining = retrainingStats.lastRetraining ?? Date()
        let interval = getRequiredInterval(frequency: schedule.frequency)
        return lastRetraining.addingTimeInterval(interval)
    }

    private func executeRetrainingJob(jobId: String, modelType: ModelInfo.ModelType) async {
        guard var job = activeJobs[jobId] else { return }

        job = RetrainingJob(
            jobId: job.jobId,
            modelType: job.modelType,
            status: .running,
            startedAt: job.startedAt,
            completedAt: nil,
            progress: 0.1,
            error: nil
        )
        activeJobs[jobId] = job

        do {
            logger.info(component: "RetrainingPipeline", event: "Starting retraining job", data: [
                "jobId": jobId,
                "modelType": modelType.rawValue
            ])

            let trainingData = try await dataIngestionService.getHistoricalData(
                for: "BTC-USD",
                from: Date().addingTimeInterval(-86400 * 30), // 30 days
                to: Date()
            )

            guard trainingData.count >= 100 else {
                throw RetrainingError.insufficientData
            }

            job = RetrainingJob(
                jobId: job.jobId,
                modelType: job.modelType,
                status: .running,
                startedAt: job.startedAt,
                completedAt: nil,
                progress: 0.3,
                error: nil
            )
            activeJobs[jobId] = job

            let modelTypeEnum = convertModelType(modelType)
            let bootstrapResult = try await bootstrapTrainer.bootstrapModel(
                for: modelTypeEnum,
                trainingData: trainingData
            )

            job = RetrainingJob(
                jobId: job.jobId,
                modelType: job.modelType,
                status: .running,
                startedAt: job.startedAt,
                completedAt: nil,
                progress: 0.7,
                error: nil
            )
            activeJobs[jobId] = job

            let deploymentStrategy = determineDeploymentStrategy(
                currentModel: modelManager.getActiveModel(for: modelType),
                newModel: bootstrapResult.modelInfo
            )

            try await modelManager.deployModel(bootstrapResult.modelInfo, strategy: deploymentStrategy)

            job = RetrainingJob(
                jobId: job.jobId,
                modelType: job.modelType,
                status: .completed,
                startedAt: job.startedAt,
                completedAt: Date(),
                progress: 1.0,
                error: nil
            )
            activeJobs[jobId] = job

            retrainingStats.recordSuccessfulRetraining()

            logger.info(component: "RetrainingPipeline", event: "Retraining job completed successfully", data: [
                "jobId": jobId,
                "modelType": modelType.rawValue,
                "accuracy": String(bootstrapResult.validationResult.accuracy)
            ])

        } catch {
            job = RetrainingJob(
                jobId: job.jobId,
                modelType: job.modelType,
                status: .failed,
                startedAt: job.startedAt,
                completedAt: Date(),
                progress: 0.0,
                error: error.localizedDescription
            )
            activeJobs[jobId] = job

            retrainingStats.recordFailedRetraining()

            logger.error(component: "RetrainingPipeline", event: "Retraining job failed", data: [
                "jobId": jobId,
                "modelType": modelType.rawValue,
                "error": error.localizedDescription
            ])
        }

        activeJobs.removeValue(forKey: jobId)
    }

    private func determineDeploymentStrategy(currentModel: ModelInfo?, newModel: ModelInfo) -> DeploymentStrategy {
        guard let current = currentModel else {
            return .immediate
        }

        let accuracyImprovement = newModel.accuracy - current.accuracy

        if accuracyImprovement > 0.05 {
            return .immediate
        } else if accuracyImprovement > 0.02 {
            return .canary
        } else {
            return .shadow
        }
    }

    private func convertModelType(_ modelType: ModelInfo.ModelType) -> ModelType {
        switch modelType {
        case .pricePrediction:
            return .pricePrediction
        case .volatilityPrediction:
            return .volatilityPrediction
        case .trendClassification:
            return .trendClassification
        case .patternRecognition:
            return .patternRecognition
        }
    }
}

public protocol DriftDetectionProtocol {
    func detectDrift(modelId: String, newData: [MarketDataPoint]) async throws -> DriftResult
    func calculateDriftScore(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double
}

public protocol PerformanceMonitoringProtocol {
    func monitorModelPerformance(modelId: String) async throws -> TrainingModelPerformance
    func shouldRetrain(modelId: String, performance: TrainingModelPerformance) -> Bool
}



public struct RetrainingStats {
    public var totalRetrainings: Int = 0
    public var successfulRetrainings: Int = 0
    public var failedRetrainings: Int = 0
    public var lastRetraining: Date?

    public mutating func recordSuccessfulRetraining() {
        totalRetrainings += 1
        successfulRetrainings += 1
        lastRetraining = Date()
    }

    public mutating func recordFailedRetraining() {
        totalRetrainings += 1
        failedRetrainings += 1
    }
}

public enum RetrainingError: Error {
    case noScheduleConfigured
    case insufficientData
    case retrainingInProgress
    case invalidModelType
    case driftDetectionFailed
    case performanceMonitoringFailed
}
