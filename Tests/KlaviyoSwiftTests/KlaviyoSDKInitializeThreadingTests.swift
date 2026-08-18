//
//  KlaviyoSDKInitializeThreadingTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import UserNotifications
import XCTest

/// Regression coverage for the off-main `Store` construction bug: calling `initialize(with:)`
/// from a background thread previously touched `klaviyoSwiftEnvironment` synchronously on that
/// thread — forcing `Store.production` construction off-main, violating the `Store`'s
/// main-thread-only invariant. All store-touching work during `initialize` must be routed to the
/// main thread regardless of the caller's thread.
@MainActor
final class KlaviyoSDKInitializeThreadingTests: XCTestCase {
    private var savedCoreEnvironment: KlaviyoEnvironment!
    private var savedEnvironment: KlaviyoSwiftEnvironment!

    override func setUp() {
        super.setUp()
        savedCoreEnvironment = environment
        savedEnvironment = klaviyoSwiftEnvironment
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    override func tearDown() {
        environment = savedCoreEnvironment
        klaviyoSwiftEnvironment = savedEnvironment
        super.tearDown()
    }

    /// Initializing from a background thread must still route store-touching work
    /// (the `statePublisher` subscription feeding `StateChangePublisher` and the `.initialize`
    /// send) to the main thread, since `Store` is main-thread-only. The stubbed `send`/`statePublisher`
    /// keep the shared `testStore` untouched, and the `wait(for:)` drains both scheduled main-actor
    /// hops before the test returns so nothing leaks into later tests.
    func testInitializeFromBackgroundThreadTouchesStoreOnMainThread() {
        let statePublisherExpectation = expectation(description: "statePublisher invoked")
        let sendExpectation = expectation(description: "send invoked")

        let lock = NSLock()
        var statePublisherOnMain = false
        var sendOnMain = false

        klaviyoSwiftEnvironment.statePublisher = {
            lock.lock(); statePublisherOnMain = Thread.isMainThread; lock.unlock()
            statePublisherExpectation.fulfill()
            return Empty<KlaviyoState, Never>().eraseToAnyPublisher()
        }
        klaviyoSwiftEnvironment.send = { _ in
            lock.lock(); sendOnMain = Thread.isMainThread; lock.unlock()
            sendExpectation.fulfill()
            return nil
        }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = KlaviyoSDK().initialize(with: "test-api-key")
        }

        wait(for: [statePublisherExpectation, sendExpectation], timeout: 2.0)

        lock.lock()
        defer { lock.unlock() }
        XCTAssertTrue(statePublisherOnMain, "the statePublisher subscription must touch the store on the main thread")
        XCTAssertTrue(sendOnMain, "initialize action must be sent on the main thread")
    }

    /// The notification-delegate injection must complete synchronously when invoked on the main
    /// thread — `initialize(with:)` relies on this so the delegate is in place before the app
    /// finishes launching. Exercises the real production closure directly (not through
    /// `initialize`, which would leak an undrained `.initialize` send + `setup()` Task into the
    /// next test) against a mock center.
    ///
    /// The synchronous guarantee only holds on iOS 17+, where the closure uses
    /// `MainActor.assumeIsolated`; on earlier OSes it hops via `Task` and the delegate is installed
    /// asynchronously, so the assertion is scoped to iOS 17+.
    func testInjectNotificationDelegateInstallsDelegateSynchronouslyOnMain() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Synchronous injection is only guaranteed on iOS 17+; earlier OSes hop via Task.")
        }

        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoSwiftEnvironment.production.injectNotificationDelegate()

        XCTAssertTrue(
            mockCenter.delegate === KlaviyoNotificationDelegate.shared,
            "injectNotificationDelegate must install the delegate synchronously on the main thread"
        )
    }
}
