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
/// thread — forcing `Store.production` construction and installing the `SharedStoreMirror` Combine
/// sink off-main, violating the `Store`'s main-thread-only invariant. All store-touching work
/// during `initialize` must be routed to the main thread regardless of the caller's thread.
@MainActor
final class KlaviyoSDKInitializeThreadingTests: XCTestCase {
    private var savedEnvironment: KlaviyoSwiftEnvironment!

    override func setUp() {
        super.setUp()
        savedEnvironment = klaviyoSwiftEnvironment
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        SharedStoreMirror.reset()
    }

    override func tearDown() {
        SharedStoreMirror.reset()
        klaviyoSwiftEnvironment = savedEnvironment
        super.tearDown()
    }

    /// Initializing from a background thread must still route store-touching work
    /// (`SharedStoreMirror.setup()`'s `statePublisher` subscription and the `.initialize` send)
    /// to the main thread, since `Store` is main-thread-only.
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
        XCTAssertTrue(statePublisherOnMain, "SharedStoreMirror.setup() must touch the store on the main thread")
        XCTAssertTrue(sendOnMain, "initialize action must be sent on the main thread")
    }

    /// The notification-delegate injection must complete synchronously before `initialize`
    /// returns when called on the main thread — the delegate has to be in place before the app
    /// finishes launching. This exercises the real production closure (the synchronous
    /// main-thread path), not a stub, so a regression that made injection async would fail here.
    func testInitializeOnMainThreadInjectsDelegateSynchronouslyBeforeReturning() {
        // Restore the production injection closure (setUp swaps in the no-op test stub) so we
        // test the actual threading behavior, but enable auto-tracking against a mock center so
        // no real UNUserNotificationCenter is touched.
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        klaviyoSwiftEnvironment.injectNotificationDelegate =
            KlaviyoSwiftEnvironment.production.injectNotificationDelegate

        _ = KlaviyoSDK().initialize(with: "test-api-key")

        XCTAssertTrue(
            mockCenter.delegate === KlaviyoNotificationDelegate.shared,
            "injectNotificationDelegate must install the delegate synchronously before initialize returns on main"
        )
    }
}
