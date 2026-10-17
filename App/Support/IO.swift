import Foundation

/// Runs file work on its own pool of threads.
///
/// File and iCloud calls can block for a long time. If they ran on the threads Swift concurrency uses
/// for everything else, a slow or offline iCloud could freeze the whole app. This queue grows its own threads instead.
enum IO {
    private static let queue = DispatchQueue(label: "lamplight.io", qos: .userInitiated, attributes: .concurrent)

    static func run<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    static func runThrowing<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
