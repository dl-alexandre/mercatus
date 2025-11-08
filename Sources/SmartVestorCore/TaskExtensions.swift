import Foundation

final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?

    init() {
        self.value = nil
    }
}

public enum TaskBlocking {
    public static func runBlocking<T>(operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<T>()
        nonisolated(unsafe) let unsafeOperation = operation

        Task { @MainActor in
            do {
                let value = try await unsafeOperation()
                resultBox.value = .success(value)
            } catch {
                resultBox.value = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        switch resultBox.value! {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

// Provide extension for backward compatibility
extension Task where Failure == Error {
    static func runBlocking<T>(operation: @escaping () async throws -> T) throws -> T {
        return try TaskBlocking.runBlocking(operation: operation)
    }
}
