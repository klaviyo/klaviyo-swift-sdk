//
//  KlaviyoNotificationDelegateTests.swift
//  KlaviyoSwiftTests
//
//  Created by Glenn Brannelly on 5/21/26.
//

@testable import KlaviyoSwift
import UserNotifications

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

#if canImport(Testing)
import Testing

// Note: the `klaviyo_automatic_push_tracking` plist key itself is verified manually
// in the example app — `Bundle.main` in the test runner never carries it, and making
// `Bundle` injectable would add abstraction beyond the current ticket's scope.

@Suite
@MainActor
struct KlaviyoNotificationDelegateTests {
    init() {
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        KlaviyoNotificationDelegate.shared.clearAutoTracked()
    }

    // MARK: - Injection Wiring

    /// Verifies that `initialize(with:)` calls `injectNotificationDelegate` exactly once,
    /// ensuring proxy installation is always attempted at SDK initialization time.
    @Test
    func initializeTriggersNotificationDelegateInjection() {
        var callCount = 0
        klaviyoSwiftEnvironment.injectNotificationDelegate = { callCount += 1 }

        KlaviyoSDK().initialize(with: "test-key")

        #expect(callCount == 1)
    }

    // MARK: - Plist Gating

    /// When automatic push tracking is disabled (the default), `injectIfEnabled()` must
    /// not install the proxy — the notification center's delegate must remain unchanged.
    @Test
    func injectIfEnabledIsNoOpWhenTrackingDisabled() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { false }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        #expect(mockCenter.delegate == nil)
    }

    // MARK: - inject(into:) Behavior

    /// After injection, the proxy must be the center's active delegate.
    @Test
    func injectSetsDelegateOnCenter() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        #expect(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
    }

    /// The delegate active at injection time must be captured as `existingDelegate`
    /// so callbacks can be forwarded to it after the proxy handles them.
    @Test
    func injectCapturesPriorDelegate() {
        let mockCenter = MockNotificationCenter()
        let priorDelegate = MockUNDelegate()
        mockCenter.delegate = priorDelegate
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        #expect(KlaviyoNotificationDelegate.shared.existingDelegate === priorDelegate)
    }

    /// A second `injectIfEnabled()` call while the proxy is already the active delegate
    /// must be a no-op — no duplicate observation tokens, no delegate reassignment.
    @Test
    func injectIsIdempotent() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()
        KlaviyoNotificationDelegate.injectIfEnabled()

        #expect(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
    }

    // MARK: - KVO Re-injection

    /// When the host app overwrites `UNUserNotificationCenter.delegate` after injection
    /// (e.g. SceneDelegate scenario), the proxy must re-install itself and capture the
    /// new host delegate as `existingDelegate`.
    @Test
    func observerReinstallsProxyAfterHostReassignment() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()

        let newHostDelegate = MockUNDelegate()
        mockCenter.simulateDelegateReassignment(to: newHostDelegate)

        #expect(mockCenter.delegate === KlaviyoNotificationDelegate.shared)
        #expect(KlaviyoNotificationDelegate.shared.existingDelegate === newHostDelegate)
    }

    // MARK: - Auto-track guard passthroughs

    /// After marking a request ID as auto-tracked, `wasAutoTracked` must return true.
    @Test
    func markAsAutoTrackedRoundTrip() {
        let delegate = KlaviyoNotificationDelegate.shared
        defer { delegate.clearAutoTracked() }

        delegate.markAsAutoTracked(requestId: "test-id")

        #expect(delegate.wasAutoTracked(requestId: "test-id"))
    }

    /// A request ID that was never marked must not appear as auto-tracked.
    @Test
    func wasAutoTrackedReturnsFalseForUnmarkedId() {
        let delegate = KlaviyoNotificationDelegate.shared
        defer { delegate.clearAutoTracked() }
        #expect(!delegate.wasAutoTracked(requestId: "never-marked"))
    }
}
#endif
