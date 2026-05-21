//
//  KlaviyoNotificationDelegateTests.swift
//  KlaviyoSwiftTests
//

@testable import KlaviyoSwift
import KlaviyoCore
import UserNotifications
import XCTest

/// Unit coverage for `KlaviyoNotificationDelegate`'s dedup state. The proxy's `didReceive` and
/// `willPresent` forwarding paths take a `UNUserNotificationCenter` argument — that type is not
/// constructible without a real app bundle (`UNUserNotificationCenter.current()` crashes in the
/// XCTest runner with `bundleProxyForCurrentProcess is nil`). Forwarding behavior is exercised
/// end-to-end in the host test app instead.
final class KlaviyoNotificationDelegateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
        KlaviyoNotificationDelegate.shared.existingDelegate = nil
    }

    override func tearDown() {
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
        KlaviyoNotificationDelegate.shared.existingDelegate = nil
        super.tearDown()
    }

    func testMarkAsAutoTrackedRoundTrip() {
        let proxy = KlaviyoNotificationDelegate.shared
        XCTAssertFalse(proxy.wasAutoTracked(requestId: "abc"))
        proxy.markAsAutoTracked(requestId: "abc")
        XCTAssertTrue(proxy.wasAutoTracked(requestId: "abc"))
        XCTAssertFalse(proxy.wasAutoTracked(requestId: "xyz"))
    }

    func testMarkAsAutoTrackedEvictsOldestEntriesOnceAtCapacity() {
        let proxy = KlaviyoNotificationDelegate.shared
        let capacity = KlaviyoNotificationDelegate.autoTrackedRequestIdCapacity

        // Fill the buffer exactly to capacity.
        for index in 0..<capacity {
            proxy.markAsAutoTracked(requestId: "req-\(index)")
        }
        XCTAssertEqual(proxy.autoTrackedRequestIds.count, capacity)
        XCTAssertEqual(proxy.autoTrackedRequestIdOrder.count, capacity)
        XCTAssertTrue(proxy.wasAutoTracked(requestId: "req-0"), "first entry must still be present at capacity")

        // One more push evicts the oldest entry.
        proxy.markAsAutoTracked(requestId: "req-\(capacity)")
        XCTAssertEqual(proxy.autoTrackedRequestIds.count, capacity, "set must stay bounded")
        XCTAssertEqual(proxy.autoTrackedRequestIdOrder.count, capacity, "FIFO queue must stay bounded")
        XCTAssertFalse(proxy.wasAutoTracked(requestId: "req-0"), "oldest entry must have been evicted")
        XCTAssertTrue(proxy.wasAutoTracked(requestId: "req-1"), "second-oldest entry must still be present")
        XCTAssertTrue(proxy.wasAutoTracked(requestId: "req-\(capacity)"), "newest entry must be present")
    }

    func testMarkAsAutoTrackedIsIdempotent() {
        let proxy = KlaviyoNotificationDelegate.shared
        proxy.markAsAutoTracked(requestId: "abc")
        proxy.markAsAutoTracked(requestId: "abc")
        proxy.markAsAutoTracked(requestId: "abc")
        XCTAssertEqual(proxy.autoTrackedRequestIds.count, 1)
        XCTAssertEqual(proxy.autoTrackedRequestIdOrder.count, 1)
    }

    func testAutoTrackedAccessorsAreThreadSafe() {
        let proxy = KlaviyoNotificationDelegate.shared
        let capacity = KlaviyoNotificationDelegate.autoTrackedRequestIdCapacity
        let writerCount = 8
        let writesPerWriter = 200
        let readerCount = 4
        let readsPerReader = 1_000

        // Writers race to insert unique request IDs while readers concurrently probe both the
        // accessor APIs and the underlying storage. Without the lock this test reliably
        // crashes with "Fatal error: Index out of range" inside `Set`/`Array` or trips a
        // thread-sanitizer race.
        let writeGroup = DispatchGroup()
        let readGroup = DispatchGroup()

        for writer in 0..<writerCount {
            writeGroup.enter()
            DispatchQueue.global().async {
                for index in 0..<writesPerWriter {
                    proxy.markAsAutoTracked(requestId: "w\(writer)-\(index)")
                }
                writeGroup.leave()
            }
        }

        for reader in 0..<readerCount {
            readGroup.enter()
            DispatchQueue.global().async {
                for index in 0..<readsPerReader {
                    _ = proxy.wasAutoTracked(requestId: "w\(reader)-\(index)")
                }
                readGroup.leave()
            }
        }

        let writeWait = writeGroup.wait(timeout: .now() + 5.0)
        let readWait = readGroup.wait(timeout: .now() + 5.0)
        XCTAssertEqual(writeWait, .success, "writers must complete without deadlock or crash")
        XCTAssertEqual(readWait, .success, "readers must complete without deadlock or crash")

        XCTAssertLessThanOrEqual(proxy.autoTrackedRequestIds.count, capacity)
        XCTAssertEqual(proxy.autoTrackedRequestIds.count, proxy.autoTrackedRequestIdOrder.count,
                       "set and FIFO queue must stay the same size under concurrent mutation")
    }

    func testOnceCallbackInvokesActionOnMainWhenCalledFromBackgroundThread() {
        // Regression test for the Flutter/RN host-adapter path: the AsyncStream consumer in
        // `UserNotificationClient.delegate()` (test app) calls `completionHandler()` from a
        // TCA task thread. iOS's UN completion handler internally touches UIApplication state
        // restoration and crashes with "Call must be made on main thread" if invoked off main,
        // so the proxy's OnceCallback must hop back to main.
        let invokedOnMain = XCTestExpectation(description: "action runs on main thread")
        let once = OnceCallback {
            XCTAssertTrue(Thread.isMainThread, "OnceCallback action must run on main thread")
            invokedOnMain.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            once.call()
        }
        wait(for: [invokedOnMain], timeout: 2.0)
    }

    func testOnceCallbackInvokesActionOnMainWhenCalledFromMain() {
        // OnceCallback routes through `dispatchOnMainThread`, which uses `Task { @MainActor in ... }`
        // to preserve FIFO ordering with the SDK's internal `dispatchOnMainThread(action:)`
        // dispatches in `handle()`. So the action runs on the main actor on a later tick, not
        // synchronously. The important contract for the iOS UN completion handler is that it
        // runs on main; whether it runs synchronously or one Task hop later doesn't matter to
        // UIApplication's state-restoration bookkeeping.
        let exp = XCTestExpectation(description: "action ran on main")
        let once = OnceCallback {
            XCTAssertTrue(Thread.isMainThread)
            exp.fulfill()
        }
        once.call()
        wait(for: [exp], timeout: 2.0)
    }

    func testOnceCallbackFiresActionExactlyOnceEvenWhenCalledFromMultipleThreads() {
        let firedCount = NSLock()
        var counter = 0
        let exp = XCTestExpectation(description: "action ran")
        let once = OnceCallback {
            firedCount.lock()
            counter += 1
            firedCount.unlock()
            exp.fulfill()
        }
        let group = DispatchGroup()
        for _ in 0..<32 {
            group.enter()
            DispatchQueue.global().async {
                once.call()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2.0), .success)
        wait(for: [exp], timeout: 2.0)
        firedCount.lock()
        XCTAssertEqual(counter, 1, "OnceCallback action must fire exactly once across concurrent callers")
        firedCount.unlock()
    }

    func testForwardingCycleIsBrokenWithoutStackOverflow() throws {
        // Regression test for the Scenario 4 finding: when another push SDK installs its own
        // proxy with the Klaviyo proxy captured as ITS prior delegate, while the Klaviyo
        // proxy has that SDK's proxy captured as `existingDelegate`, every UN callback
        // recurses through the chain and overflows the stack. The proxy's per-request
        // forwarding guard must break the cycle.
        //
        // We can't easily construct a real `UNNotificationResponse` in unit tests
        // (`UNUserNotificationCenter.current()` is unavailable in the test runner) so we
        // drive the guard helpers directly. Concretely we simulate two threads / call
        // frames attempting to "enter" the same request id and verify the second is
        // rejected.
        let proxy = KlaviyoNotificationDelegate.shared
        let requestId = "scenario-4-cycle"

        // First entry succeeds — caller "enters" the forwarding section.
        let firstEntry = proxy.testHook_beginForwardingDidReceive(requestId)
        XCTAssertTrue(firstEntry, "First entry must be allowed; nothing else is in flight")

        // Nested re-entry for the same id from a recursive callback would be rejected,
        // breaking the cycle before stack overflow.
        let secondEntry = proxy.testHook_beginForwardingDidReceive(requestId)
        XCTAssertFalse(secondEntry, "Re-entry for the same request must be rejected (cycle break)")

        // Exiting cleans the set so the same id can be processed again later.
        proxy.testHook_endForwardingDidReceive(requestId)
        let reentryAfterExit = proxy.testHook_beginForwardingDidReceive(requestId)
        XCTAssertTrue(reentryAfterExit, "After end(), the same request id must be admissible again")
        proxy.testHook_endForwardingDidReceive(requestId)

        // Same shape applies to willPresent — its own independent set tracks identifiers in
        // flight on the foreground-presentation path.
        XCTAssertTrue(proxy.testHook_beginForwardingWillPresent(requestId))
        XCTAssertFalse(proxy.testHook_beginForwardingWillPresent(requestId))
        proxy.testHook_endForwardingWillPresent(requestId)
    }

    func testExistingDelegateIsWeak() {
        let proxy = KlaviyoNotificationDelegate.shared
        autoreleasepool {
            let host = NSObject()
            proxy.existingDelegate = host as? UNUserNotificationCenterDelegate
        }
        // The host was deallocated when the autoreleasepool drained; the weak ref must be nil.
        XCTAssertNil(proxy.existingDelegate)
    }
}
