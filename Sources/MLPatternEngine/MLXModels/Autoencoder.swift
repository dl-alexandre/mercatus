import Foundation
import MLX
import MLXNN
import Utils

public class PriceAutoencoder: Module {
    @ModuleInfo var encoder1: Linear
    @ModuleInfo var encoder2: Linear
    @ModuleInfo var decoder1: Linear
    @ModuleInfo var decoder2: Linear

    private let inputSize: Int
    private let latentSize: Int

    public init(inputSize: Int = 18, latentSize: Int = 8) {
        self.inputSize = inputSize
        self.latentSize = latentSize

        self.encoder1 = Linear(inputSize, 64)
        self.encoder2 = Linear(64, latentSize)
        self.decoder1 = Linear(latentSize, 64)
        self.decoder2 = Linear(64, inputSize)

        super.init()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let encoded = relu(encoder2(relu(encoder1(x))))
        let decoded = decoder2(relu(decoder1(encoded)))
        return decoded
    }

    public func encode(_ x: MLXArray) -> MLXArray {
        return relu(encoder2(relu(encoder1(x))))
    }

    public func decode(_ z: MLXArray) -> MLXArray {
        return decoder2(relu(decoder1(z)))
    }
}

public class AnomalyDetector {
    private let autoencoder: PriceAutoencoder
    private let threshold: Float
    private let logger: StructuredLogger

    public init(autoencoder: PriceAutoencoder, threshold: Float = 0.1, logger: StructuredLogger) {
        self.autoencoder = autoencoder
        self.threshold = threshold
        self.logger = logger
    }

    public func detectAnomaly(input: [Double]) throws -> (isAnomaly: Bool, reconstructionError: Double) {
        let inputArray = MLXArray(input.map { Float($0) }, [1, input.count])
        let reconstructed = autoencoder(inputArray)

        try withError { error in
            eval(reconstructed)
            try error.check()
        }

        let diff = inputArray - reconstructed
        let error = (diff * diff).mean()
        let errorValue = error.item(Float.self)

        return (errorValue > threshold, Double(errorValue))
    }
}
