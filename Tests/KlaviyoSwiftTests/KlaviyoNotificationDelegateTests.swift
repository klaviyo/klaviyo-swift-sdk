//
//  KlaviyoNotificationDelegateTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 5/21/26.
//

@testable import KlaviyoSwift
import UserNotifications
import XCTest

// MARK: - Test Doubles

/// Minimal `UNUserNotificationCenterDelegate` conformer used for object-identity assertions.
final class MockUNDelegate: NSObject, UNUserNotificationCenterDelegate {}

/// Stands in for `UNUserNotificationCenter` in unit tests.
///
/// The real center requires an app-bundle context (`current()` crashes in the SPM test
/// runner). This mock captures the observation handler so tests can fire it directly,
/// simulating the host app reassigning `UNUserNotificationCenter.delegate` after injection.
@MainActor
final class MockNotificationCenter: UserNotificationCenterProtocol {
    var delegate: (any UNUserNotificationCenterDelegate)?
    private var observationHandler: (@MainActor () -> Void)?

    func observeDelegate(using handler: @escaping @MainActor () -> Void) -> AnyObject {
        observationHandler = handler
        return NSObject()
    }

    /// Simulates the host app overwriting `UNUserNotificationCenter.delegate` after
    /// the proxy has been installed (e.g. in `SceneDelegate.scene(_:willConnectTo:)`).
    func simulateDelegateReassignment(to newDelegate: (any UNUserNotificationCenterDelegate)?) {
        delegate = newDelegate
        observationHandler?()
    }
}

// MARK: - Tests

// Note: plist key behavior is verified manually in the example app — `Bundle.main` is not
// available in the test runner, so flag values are controlled via `KlaviyoSwiftEnvironment`.

@MainActor
class KlaviyoNotificationDelegateTests: XCTestCase {
    override func setUpWithError() throws {
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
    }

    // MARK: - Injection Wiring

    /// Verifies that `initialize(with:)` calls `injectNotificationDelegate` exactly once,
    /// ensuring proxy installation is always attempted at SDK initialization time.
    func testInitializeTriggersNotificationDelegateInjection() {
        var callCount = 0
        klaviyoSwiftEnvironment.injectNotificationDelegate = { callCount += 1 }
        // initialize(with:) dispatches its action asynchronously. Wait for it here so the
        // action is fully drained before this test returns — otherwise it lands in the next
        // test's send handler and causes a spurious assertion failure.
        let actionFired = XCTestExpectation(description: "initialize action dispatched")
        klaviyoSwiftEnvironment.send = { _ in actionFired.fulfill(); return nil }

        KlaviyoSDK().initialize(with: "test-key")

        wait(for: [actionFired], timeout: 1.0)
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Plist Gating

    /// Both flags off: `injectIfEnabled()` is a no-op and the proxy delegate is never installed.
    func testInjectIfEnabledIsNoOpWhenBothFlagsDisabled() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { false }
        klaviyoSwiftEnvironment.isAutomaticTokenForwardingEnabled = { false }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertNil(mockCenter.delegate)
    }

    // MARK: - inject(into:) Behavior

    /// After injection, the proxy must be the center's active delegate.
    func testInjectSetsDelegateOnCenter() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertTrue(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
    }

    /// The delegate active at injection time must be captured as `existingDelegate`
    /// so callbacks can be forwarded to it after the proxy handles them.
    func testInjectCapturesPriorDelegate() {
        let mockCenter = MockNotificationCenter()
        let priorDelegate = MockUNDelegate()
        mockCenter.delegate = priorDelegate
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertTrue(KlaviyoNotificationDelegate.shared.existingDelegate === priorDelegate)
    }

    /// A second `injectIfEnabled()` call while the proxy is already the active delegate
    /// must be a no-op — no duplicate observation tokens, no delegate reassignment.
    func testInjectIsIdempotent() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()
        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertTrue(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
    }

    // MARK: - KVO Re-injection

    /// When the host app overwrites `UNUserNotificationCenter.delegate` after injection
    /// (e.g. SceneDelegate scenario), the proxy must re-install itself and capture the
    /// new host delegate as `existingDelegate`.
    func testObserverReinstallsProxyAfterHostReassignment() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()

        let newHostDelegate = MockUNDelegate()
        mockCenter.simulateDelegateReassignment(to: newHostDelegate)

        XCTAssertTrue(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
        XCTAssertTrue(KlaviyoNotificationDelegate.shared.existingDelegate === newHostDelegate)
    }

    // MARK: - Auto-track guard passthroughs

    /// After marking a dedup key as auto-tracked, `wasAutoTracked` must return true.
    func testMarkAsAutoTrackedRoundTrip() {
        // Given
        let delegate = KlaviyoNotificationDelegate.shared
        defer { delegate.clearAutoTracked() }

        // When
        delegate.markAsAutoTracked(dedupKey: "test-id")

        // Then
        XCTAssertTrue(delegate.wasAutoTracked(dedupKey: "test-id"))
    }

    /// A dedup key that was never marked must not appear as auto-tracked.
    func testWasAutoTrackedReturnsFalseForUnmarkedId() {
        // Given
        let delegate = KlaviyoNotificationDelegate.shared
        defer { delegate.clearAutoTracked() }

        // When / Then
        XCTAssertFalse(delegate.wasAutoTracked(dedupKey: "never-marked"))
    }
}
