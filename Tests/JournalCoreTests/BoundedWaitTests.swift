import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class BoundedWaitTests: XCTestCase {
    private struct Failure: Error {}

    /// Work that takes a while, as a read does when iCloud is holding it up.
    private func slow(_ seconds: TimeInterval) -> () throws -> Int {
        { Thread.sleep(forTimeInterval: seconds); return 1 }
    }

    private func seconds(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }

    func testReturnsWhatTheWorkReturns() throws {
        let bounded = BoundedWait()
        XCTAssertEqual(try bounded.run(timeout: 5) { 42 }, 42)
    }

    func testRethrowsWhatTheWorkThrows() {
        let bounded = BoundedWait()
        XCTAssertThrowsError(try bounded.run(timeout: 5) { throw Failure() }) { error in
            XCTAssertTrue(error is Failure)
        }
    }

    func testStopsWaitingForWorkThatTakesTooLong() {
        let bounded = BoundedWait()
        var thrown: Error?
        let elapsed = seconds {
            do { _ = try bounded.run(timeout: 0.1, slow(2)) } catch { thrown = error }
        }
        XCTAssertEqual(thrown as? FileWaitError, .timedOut)
        XCTAssertLessThan(elapsed, 1)
    }

    func testCancelsWhenItGivesUp() {
        let bounded = BoundedWait()
        let cancelled = expectation(description: "cancelled")
        _ = try? bounded.run(timeout: 0.05, cancel: { cancelled.fulfill() }, slow(0.5))
        wait(for: [cancelled], timeout: 1)
    }

    func testDoesNotCancelWorkThatFinishes() throws {
        let bounded = BoundedWait()
        let cancelled = expectation(description: "cancelled")
        cancelled.isInverted = true
        _ = try bounded.run(timeout: 5, cancel: { cancelled.fulfill() }) { 1 }
        wait(for: [cancelled], timeout: 0.1)
    }

    func testRefusesWorkAfterSeveralWaitsInARunOutAndRecoversAfterThePause() throws {
        let bounded = BoundedWait(failuresBeforePause: 2, pause: 0.4)
        for _ in 0..<2 { _ = try? bounded.run(timeout: 0.05, slow(0.3)) }

        var thrown: Error?
        let refusal = seconds {
            do { _ = try bounded.run(timeout: 5) { 1 } } catch { thrown = error }
        }
        XCTAssertEqual(thrown as? FileWaitError, .paused)
        XCTAssertLessThan(refusal, 0.1)

        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(try bounded.run(timeout: 5) { 7 }, 7)
    }

    func testAnAnswerPutsTheCountBackToZero() throws {
        let bounded = BoundedWait(failuresBeforePause: 2, pause: 5)
        _ = try? bounded.run(timeout: 0.05, slow(0.3))
        XCTAssertEqual(try bounded.run(timeout: 5) { 1 }, 1)
        _ = try? bounded.run(timeout: 0.05, slow(0.3))
        // One wait ran out since the answer, so this still goes ahead.
        XCTAssertEqual(try bounded.run(timeout: 5) { 2 }, 2)
    }

    func testAnErrorFromTheWorkCountsAsAnAnswer() throws {
        let bounded = BoundedWait(failuresBeforePause: 2, pause: 5)
        _ = try? bounded.run(timeout: 0.05, slow(0.3))
        _ = try? bounded.run(timeout: 5) { throw Failure() }
        _ = try? bounded.run(timeout: 0.05, slow(0.3))
        XCTAssertEqual(try bounded.run(timeout: 5) { 3 }, 3)
    }

    func testAfterThePauseOneMoreWaitThatRunsOutPausesAgain() throws {
        let bounded = BoundedWait(failuresBeforePause: 2, pause: 0.3)
        for _ in 0..<2 { _ = try? bounded.run(timeout: 0.05, slow(0.2)) }
        Thread.sleep(forTimeInterval: 0.4)
        _ = try? bounded.run(timeout: 0.05, slow(0.2))
        XCTAssertThrowsError(try bounded.run(timeout: 5) { 1 }) { error in
            XCTAssertEqual(error as? FileWaitError, .paused)
        }
    }
}
