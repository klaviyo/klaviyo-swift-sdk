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
private final class MockUNDelegate: NSObject, UNUserNotificationCenterDelegate {}

private final class CallbackBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private final class AsyncUNDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var didReceiveCompletion: (@Sendable () -> Void)?
    var willPresentCompletion: (@Sendable (UNNotificationPresentationOptions) -> Void)?
    var openSettingsCallCount = 0

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        didReceiveCompletion = completionHandler
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        willPresentCompletion = completionHandler
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        openSettingsCallCount += 1
    }
}

private final class ManualKlaviyoHandlingDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let handled = KlaviyoSDK().handle(
            notificationResponse: response,
            withCompletionHandler: completionHandler
        )
        if !handled {
            completionHandler()
        }
    }
}

/// A third-party proxy that captures whatever delegate is installed when it observes (here,
/// Klaviyo's proxy), then forwards every callback into it before completing on its own —
/// i.e. it re-enters `KlaviyoNotificationDelegate` synchronously on the same request.
private final class ForwardingProxyDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    weak var originalDelegate: (any UNUserNotificationCenterDelegate)?
    var willPresentCallCount = 0
    var didReceiveCallCount = 0

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        willPresentCallCount += 1
        guard let originalDelegate, originalDelegate.responds(
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(
                _:willPresent:withCompletionHandler:
            ))
        ) else {
            completionHandler([])
            return
        }
        originalDelegate.userNotificationCenter?(
            center, willPresent: notification, withCompletionHandler: completionHandler
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        didReceiveCallCount += 1
        guard let originalDelegate, originalDelegate.responds(
            to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(
                _:didReceive:withCompletionHandler:
            ))
        ) else {
            completionHandler()
            return
        }
        originalDelegate.userNotificationCenter?(
            center, didReceive: response, withCompletionHandler: completionHandler
        )
    }
}

/// Stands in for `UNUserNotificationCenter` in unit tests.
///
/// The real center requires an app-bundle context (`current()` crashes in the SPM test
/// runner). This mock captures the observation handler so tests can fire it directly,
/// simulating the host app reassigning `UNUserNotificationCenter.delegate` after injection.
@MainActor
final class MockNotificationCenter: UserNotificationCenterProtocol {
    var delegate: (any UNUserNotificationCenterDelegate)?

    /// Simulates the setter hook capturing a later host assignment and restoring the proxy.
    func simulateDelegateReassignment(to newDelegate: (any UNUserNotificationCenterDelegate)?) {
        delegate = newDelegate
        KlaviyoNotificationDelegate.shared.captureHostDelegate(newDelegate)
        delegate = KlaviyoNotificationDelegate.shared
    }
}

// MARK: - Tests

// Note: plist key behavior is verified manually in the example app — `Bundle.main` is not
// available in the test runner, so flag values are controlled via `KlaviyoSwiftEnvironment`.

@MainActor
class KlaviyoNotificationDelegateTests: XCTestCase {
    private func callbackOnlyNotificationCenter() -> UNUserNotificationCenter {
        // Delegate forwarding only passes this object through; neither proxy nor test host
        // accesses center state. The real `current()` traps in an app-less SPM test runner.
        unsafeBitCast(NSObject(), to: UNUserNotificationCenter.self)
    }

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
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { false }
        klaviyoSwiftEnvironment.isAutomaticPushTokenForwardingEnabled = { false }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertNil(mockCenter.delegate)
    }

    // MARK: - inject(into:) Behavior

    /// After injection, the proxy must be the center's active delegate.
    func testInjectSetsDelegateOnCenter() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
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
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }

        KlaviyoNotificationDelegate.injectIfEnabled()

        XCTAssertTrue(KlaviyoNotificationDelegate.shared.existingDelegate === priorDelegate)
    }

    /// A second `injectIfEnabled()` call while the proxy is already the active delegate
    /// must be a no-op — no duplicate observation tokens, no delegate reassignment.
    func testInjectIsIdempotent() {
        let mockCenter = MockNotificationCenter()
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
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
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
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

    // MARK: - Completion-safe forwarding

    func testDidReceiveLeavesCompletionOwnershipWithAsyncHostDelegate() throws {
        let hostDelegate = AsyncUNDelegate()
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = hostDelegate
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()
        let response = try UNNotificationResponse.with(userInfo: [:])
        let completionCount = CallbackBox(0)

        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            didReceive: response,
            withCompletionHandler: { completionCount.value += 1 }
        )

        XCTAssertEqual(completionCount.value, 0)
        hostDelegate.didReceiveCompletion?()
        hostDelegate.didReceiveCompletion?()
        XCTAssertEqual(completionCount.value, 1)
    }

    func testDidReceiveDismissalCompletesWhenHostUsesManualKlaviyoHandler() throws {
        let hostDelegate = ManualKlaviyoHandlingDelegate()
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = hostDelegate
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()
        let response = try UNNotificationResponse.with(
            userInfo: ["body": ["_k": ["foo": "bar"]]],
            actionIdentifier: UNNotificationDismissActionIdentifier
        )
        let completion = expectation(description: "system completion called")

        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            didReceive: response,
            withCompletionHandler: { completion.fulfill() }
        )

        wait(for: [completion], timeout: 0.1)
    }

    func testWillPresentForwardsAsyncHostOptionsUnchanged() throws {
        let hostDelegate = AsyncUNDelegate()
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = hostDelegate
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()
        let response = try UNNotificationResponse.with(userInfo: [:])
        let receivedOptions = CallbackBox<UNNotificationPresentationOptions?>(nil)

        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            willPresent: response.notification,
            withCompletionHandler: { receivedOptions.value = $0 }
        )

        XCTAssertNil(receivedOptions.value)
        hostDelegate.willPresentCompletion?([.alert, .sound])
        XCTAssertEqual(receivedOptions.value, [.alert, .sound])
    }

    func testWillPresentUsesDefaultOptionsWhenNoDelegateRespondsToWillPresent() throws {
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = MockUNDelegate()
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()
        let response = try UNNotificationResponse.with(userInfo: [:])
        let receivedOptions = CallbackBox<UNNotificationPresentationOptions?>(nil)

        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            willPresent: response.notification,
            withCompletionHandler: { receivedOptions.value = $0 }
        )

        let expected: UNNotificationPresentationOptions =
            if #available(iOS 14.0, *) { [.list, .banner, .badge, .sound] } else { [.alert, .badge, .sound] }
        XCTAssertEqual(receivedOptions.value, expected)
    }

    // MARK: - Forwarding-proxy cycle

    /// Reproduces the observed production order: the host app assigns its own delegate first,
    /// Klaviyo installs and captures it, then a third-party forwarding proxy installs
    /// afterward and captures Klaviyo's proxy as its own "original delegate." A
    /// notification arriving through the system now enters at the third-party proxy, which
    /// forwards into Klaviyo (re-entrant call), which must walk past itself in the chain and
    /// reach the real host delegate — not treat the re-entry as a cycle and drop to empty
    /// options.
    func testWillPresentReachesHostDelegateThroughForwardingProxyCycle() throws {
        let hostDelegate = AsyncUNDelegate()
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = hostDelegate
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()

        // Simulate a third-party proxy observing after Klaviyo has already installed: it
        // captures Klaviyo's proxy as `originalDelegate`, then the system's delegate slot
        // is reassigned to it. `simulateDelegateReassignment` mirrors the real setter hook,
        // which captures the assignee into Klaviyo's chain before re-asserting the proxy.
        let forwardingProxy = ForwardingProxyDelegate()
        forwardingProxy.originalDelegate = KlaviyoNotificationDelegate.shared
        mockCenter.simulateDelegateReassignment(to: forwardingProxy)

        let response = try UNNotificationResponse.with(userInfo: [:])
        let receivedOptions = CallbackBox<UNNotificationPresentationOptions?>(nil)

        // The system always calls the proxy — the setter hook keeps it as the effective
        // delegate — exactly as it would on a real device.
        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            willPresent: response.notification,
            withCompletionHandler: { receivedOptions.value = $0 }
        )

        XCTAssertEqual(forwardingProxy.willPresentCallCount, 1)
        XCTAssertNil(receivedOptions.value, "host delegate is async — should not have answered yet")

        hostDelegate.willPresentCompletion?([.alert, .sound])

        XCTAssertEqual(receivedOptions.value, [.alert, .sound])
    }

    /// Same cycle shape for `didReceive`: the open must still reach the host delegate exactly
    /// once through the proxy bounce, and Klaviyo's own auto-tracking must fire exactly once
    /// (at the outermost call), not once per re-entrant hop.
    func testDidReceiveReachesHostDelegateThroughForwardingProxyCycle() throws {
        let hostDelegate = AsyncUNDelegate()
        let mockCenter = MockNotificationCenter()
        mockCenter.delegate = hostDelegate
        klaviyoSwiftEnvironment.isAutomaticPushOpenTrackingEnabled = { true }
        klaviyoSwiftEnvironment.notificationCenter = { mockCenter }
        KlaviyoNotificationDelegate.injectIfEnabled()

        // `simulateDelegateReassignment` mirrors the real setter hook, which captures the
        // assignee into Klaviyo's chain before re-asserting the proxy.
        let forwardingProxy = ForwardingProxyDelegate()
        forwardingProxy.originalDelegate = KlaviyoNotificationDelegate.shared
        mockCenter.simulateDelegateReassignment(to: forwardingProxy)

        let response = try UNNotificationResponse.with(userInfo: [:])
        let completionCount = CallbackBox(0)

        // The system always calls the proxy — the setter hook keeps it as the effective
        // delegate — exactly as it would on a real device.
        KlaviyoNotificationDelegate.shared.userNotificationCenter(
            callbackOnlyNotificationCenter(),
            didReceive: response,
            withCompletionHandler: { completionCount.value += 1 }
        )

        XCTAssertEqual(forwardingProxy.didReceiveCallCount, 1)
        XCTAssertEqual(completionCount.value, 0)

        hostDelegate.didReceiveCompletion?()

        XCTAssertEqual(completionCount.value, 1)
    }
}
