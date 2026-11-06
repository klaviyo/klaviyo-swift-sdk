//
//  NetworkPathMonitorTests.swift
//  KlaviyoCoreTests
//

@testable import KlaviyoCore
import XCTest

/// Fake path source that captures the update handler so tests can deliver statuses synchronously.
private final class FakePathSource: NetworkPathSource {
    private(set) var startCount = 0
    private(set) var isCancelled = false
    private var onUpdate: ((Reachability.NetworkStatus) -> Void)?

    func start(queue: DispatchQueue, onUpdate: @escaping @Sendable (Reachability.NetworkStatus) -> Void) {
        startCount += 1
        self.onUpdate = onUpdate
    }

    func cancel() {
        isCancelled = true
    }

    func send(_ status: Reachability.NetworkStatus) {
        onUpdate?(status)
    }
}

final class NetworkPathMonitorTests: XCTestCase {
    private var notificationCenter: NotificationCenter!
    private var sources: [FakePathSource]!
    private var monitor: NetworkPathMonitor!
    private var postCount = 0
    private var observer: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        sources = []
        postCount = 0
        monitor = NetworkPathMonitor(notificationCenter: notificationCenter) { [unowned self] in
            let source = FakePathSource()
            sources.append(source)
            return source
        }
        observer = notificationCenter.addObserver(
            forName: ReachabilityChangedNotification,
            object: nil,
            queue: nil
        ) { [unowned self] _ in postCount += 1 }
    }

    override func tearDown() {
        observer.map(notificationCenter.removeObserver)
        monitor = nil
        sources = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testCurrentStatusIsNilBeforeFirstUpdate() {
        monitor.start()
        XCTAssertNil(monitor.currentStatus)
        XCTAssertEqual(postCount, 0)
    }

    func testUpdatePostsNotificationAndUpdatesStatus() {
        monitor.start()
        sources[0].send(.reachableViaWiFi)

        XCTAssertEqual(monitor.currentStatus, .reachableViaWiFi)
        XCTAssertEqual(postCount, 1)
    }

    func testRepeatedStatusIsDeduplicated() {
        monitor.start()
        sources[0].send(.reachableViaWiFi)
        sources[0].send(.reachableViaWiFi)
        sources[0].send(.reachableViaWWAN)
        sources[0].send(.reachableViaWWAN)
        sources[0].send(.notReachable)

        XCTAssertEqual(monitor.currentStatus, .notReachable)
        XCTAssertEqual(postCount, 3)
    }

    func testStartIsIdempotentWhileRunning() {
        monitor.start()
        monitor.start()

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].startCount, 1)
    }

    func testStopCancelsSource() {
        monitor.start()
        monitor.stop()

        XCTAssertTrue(sources[0].isCancelled)
    }

    func testRestartUsesFreshSource() {
        monitor.start()
        monitor.stop()
        monitor.start()

        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources[0].isCancelled)
        XCTAssertFalse(sources[1].isCancelled)
        XCTAssertEqual(sources[1].startCount, 1)
    }

    func testUpdatesFromStoppedSourceAreIgnored() {
        monitor.start()
        sources[0].send(.reachableViaWiFi)
        monitor.stop()
        monitor.start()

        sources[0].send(.notReachable)

        XCTAssertEqual(monitor.currentStatus, .reachableViaWiFi)
        XCTAssertEqual(postCount, 1)
    }

    func testStatusSurvivesStopAndRestartOnlyPostsOnChange() {
        monitor.start()
        sources[0].send(.reachableViaWiFi)
        monitor.stop()

        XCTAssertEqual(monitor.currentStatus, .reachableViaWiFi)

        monitor.start()
        sources[1].send(.reachableViaWiFi)
        XCTAssertEqual(postCount, 1, "an unchanged status after restart must not re-post")

        sources[1].send(.notReachable)
        XCTAssertEqual(postCount, 2)
    }
}
