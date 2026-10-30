import Foundation

/// Why a read or listing was given up on.
enum FileWaitError: Error, LocalizedError, Equatable {
    case timedOut
    case paused

    var errorDescription: String? {
        switch self {
        case .timedOut: return "iCloud didn't answer in time."
        case .paused: return "iCloud isn't answering, so this wasn't tried."
        }
    }
}

/// Runs blocking work, such as a read that iCloud is holding up, and stops waiting for it after a while.
///
/// The work can't be interrupted, so it is left to finish on its own thread and what it returns is dropped.
/// After several waits in a row that ran out, further work is refused for a short time rather than starting
/// more calls that will hang too. Any call that gets an answer, even an error, puts things back to normal.
final class BoundedWait: @unchecked Sendable {
    private let failuresBeforePause: Int
    private let pause: TimeInterval
    private let lock = NSLock()
    private var failures = 0
    private var pausedUntil: Date?

    init(failuresBeforePause: Int = 3, pause: TimeInterval = 20) {
        self.failuresBeforePause = max(1, failuresBeforePause)
        self.pause = pause
    }

    /// Runs `work` and returns what it returns, rethrowing what it throws. Throws `FileWaitError.timedOut` if it hasn't
    /// finished after `timeout` seconds, after calling `cancel` so a request still waiting its turn can be dropped.
    func run<T>(timeout: TimeInterval, cancel: @escaping () -> Void = {}, _ work: @escaping () throws -> T) throws -> T {
        if isPaused { throw FileWaitError.paused }

        let outcome = Outcome<T>()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            outcome.store(Result { try work() })
            finished.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            cancel()
            noteTimeout()
            throw FileWaitError.timedOut
        }
        noteAnswer()
        return try outcome.value().get()
    }

    private var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = pausedUntil else { return false }
        if Date() < until { return true }
        pausedUntil = nil
        return false
    }

    private func noteTimeout() {
        lock.lock()
        defer { lock.unlock() }
        failures += 1
        if failures >= failuresBeforePause {
            pausedUntil = Date().addingTimeInterval(pause)
            // After the pause, one more wait that runs out pauses again at once.
            failures = failuresBeforePause - 1
        }
    }

    private func noteAnswer() {
        lock.lock()
        defer { lock.unlock() }
        failures = 0
        pausedUntil = nil
    }

    /// Where the work leaves its result, which may arrive after the caller has stopped waiting.
    private final class Outcome<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Value, Error>?

        func store(_ result: Result<Value, Error>) {
            lock.lock()
            self.result = result
            lock.unlock()
        }

        func value() -> Result<Value, Error> {
            lock.lock()
            defer { lock.unlock() }
            return result ?? .failure(FileWaitError.timedOut)
        }
    }
}
