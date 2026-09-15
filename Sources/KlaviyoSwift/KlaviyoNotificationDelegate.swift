//
//  KlaviyoNotificationDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/13/26.
//

import Foundation
import KlaviyoCore
import OSLog
import UserNotifications

// MARK: - UserNotificationCenterProtocol

/// Abstracts notification-center delegate assignment so unit tests can supply a lightweight
/// mock without the app-bundle context that `UNUserNotificationCenter.current()` requires.
@MainActor
protocol UserNotificationCenterProtocol: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {}

// MARK: - KlaviyoNotificationDelegate

/// A proxy `UNUserNotificationCenterDelegate` that Klaviyo installs as the active
/// notification center delegate when automatic push tracking is enabled.
///
/// The proxy intercepts `didReceive` to fire the `Opened Push` event automatically,
/// then forwards every callback along an ordered chain of previously-assigned delegates,
/// preserving full host behavior as though the proxy were never there.
///
/// ## Delegate chain, not a single slot
/// Every `UNUserNotificationCenter.setDelegate:` call is captured, not just the most
/// recent one, because another forwarding proxy may capture Klaviyo's proxy as its own
/// "original delegate" and forward back into it, re-entering this class synchronously on
/// the same callback. If only the latest assignment were remembered, that re-entrant call
/// would find itself as the "existing delegate," short-circuit as a cycle, and answer with
/// empty options — silently discarding the host app's real delegate further down the
/// chain. Instead, each re-entrant call walks one step deeper into the preserved chain (see
/// `ForwardingCycleGuard`), so a Klaviyo → other-proxy → Klaviyo → host-delegate bounce
/// still reaches the host's real implementation.
///
/// ## Lifecycle
/// The pre-main installer hooks `UNUserNotificationCenter.setDelegate:` and re-installs
/// the proxy whenever anyone overwrites it, capturing the effective delegate at that
/// moment as the newest link in the chain.
///
/// ## Thread safety
/// All mutation is confined to `@MainActor`.
final class KlaviyoNotificationDelegate: NSObject {
    static let shared = KlaviyoNotificationDelegate()

    override private init() {}

    /// Wraps a delegate weakly so the chain never extends its lifetime, mirroring
    /// `UNUserNotificationCenter.delegate`'s own weak-reference contract.
    private final class WeakDelegateBox {
        weak var value: (any UNUserNotificationCenterDelegate)?
        init(_ value: any UNUserNotificationCenterDelegate) { self.value = value }
    }

    private let delegateLock = NSLock()

    /// Ordered most-recently-captured-first. Each `setDelegate:` call prepends its
    /// assignee here instead of replacing a single slot, so earlier delegates (e.g. the
    /// host app's `AppDelegate`) survive a later third-party proxy's installation.
    private var delegateChain: [WeakDelegateBox] = []

    /// The most recently captured delegate still alive, or `nil` if none is live.
    ///
    /// Exposed for tests/diagnostics. Actual forwarding walks the full `delegateChain`
    /// via `delegate(atDepth:respondingTo:)`, not just this single entry.
    var existingDelegate: (any UNUserNotificationCenterDelegate)? {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        return delegateChain.first(where: { $0.value != nil })?.value
    }

    // MARK: - Forwarding-cycle guard

    private let didReceiveGuard = ForwardingCycleGuard()
    private let willPresentGuard = ForwardingCycleGuard()

    // MARK: - Auto-track guard

    private let autoTrackGuard = BoundedIDSet<String>()

    func markAsAutoTracked(dedupKey: String) { autoTrackGuard.insert(dedupKey) }
    func wasAutoTracked(dedupKey: String) -> Bool { autoTrackGuard.contains(dedupKey) }
    func clearAutoTracked() { autoTrackGuard.clear() }

    // MARK: - Injection

    /// Reads the two independent opt-in flags and the notification center from
    /// `KlaviyoSwiftEnvironment`, then applies each behavior on its own:
    /// - `klaviyo_automatic_push_open_tracking` gates proxy injection (automatic push-open tracking).
    /// - `klaviyo_automatic_push_token_forwarding` gates app-delegate swizzling (device-token forwarding).
    ///
    /// Neither flag is a prerequisite for the other, so any combination is honored.
    ///
    /// All dependencies are environment-injected so tests can control the plist gates
    /// and substitute a mock center without requiring an app-bundle context.
    ///
    /// Called once from `KlaviyoSDK.initialize(with:)` via
    /// `KlaviyoSwiftEnvironment.injectNotificationDelegate`.
    @MainActor
    static func injectIfEnabled() {
        KlaviyoAutomaticPushInstaller.install(for: nil)
    }

    /// Installs the proxy as the active delegate after retaining the current host delegate.
    /// Future host assignments are captured synchronously by the setter hook.
    @MainActor
    func install(into center: any UserNotificationCenterProtocol) {
        guard center.delegate !== self else { return }

        if #available(iOS 14.0, *) {
            Logger.notifications.info(
                "Installing notification delegate proxy for automatic push tracking."
            )
        }
        captureHostDelegate(center.delegate)
        center.delegate = self
    }

    /// Prepends `delegate` to the chain as the newest link, pruning dead and duplicate
    /// entries first. Passing `nil` clears the entire chain (mirrors the host explicitly
    /// unsetting `UNUserNotificationCenter.delegate`).
    ///
    /// Prepending — rather than replacing a single slot — is what lets a third-party
    /// proxy's later installation coexist with an earlier host delegate: both remain
    /// reachable, in the order they were assigned, for `delegate(atDepth:respondingTo:)`
    /// to walk through on re-entrant forwarding calls.
    func captureHostDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        guard let delegate else {
            delegateChain.removeAll()
            return
        }
        guard delegate !== self else { return }
        delegateChain.removeAll { $0.value == nil || $0.value === delegate }
        delegateChain.insert(WeakDelegateBox(delegate), at: 0)
    }

    /// Returns the live delegate at `depth` in the chain that responds to `selector`,
    /// skipping over dead weak references and delegates that don't implement it.
    ///
    /// `depth` comes from `ForwardingCycleGuard.enter(_:)`: depth 0 is the newest captured
    /// delegate (the usual single-hop case), depth 1 is the next one back, and so on —
    /// each re-entrant call into this proxy for the same request ID advances one step
    /// further down the chain instead of bouncing back to the delegate that just
    /// forwarded into it.
    private func delegate(
        atDepth depth: Int,
        respondingTo selector: Selector
    ) -> (any UNUserNotificationCenterDelegate)? {
        delegateLock.lock()
        let candidates = delegateChain.compactMap(\.value)
        delegateLock.unlock()
        let responders = candidates.filter { $0 !== self && $0.responds(to: selector) }
        guard depth < responders.count else { return nil }
        return responders[depth]
    }

    /// Presentation options used when no delegate in the chain implements `willPresent`.
    /// Matches the SDK's rel/5.4 defaults so a bare Klaviyo integration (no host
    /// `UNUserNotificationCenterDelegate` at all) still shows a visible foreground banner.
    private static var defaultPresentationOptions: UNNotificationPresentationOptions {
        if #available(iOS 14.0, *) {
            return [.list, .banner, .badge, .sound]
        }
        return [.alert, .badge, .sound]
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension KlaviyoNotificationDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let requestId = response.notification.request.identifier
        let once = OnceCallback(completionHandler)
        let depth = didReceiveGuard.enter(requestId)
        defer { didReceiveGuard.leave(requestId) }

        // Only the outermost call tracks the open — a re-entrant call at depth > 0 means
        // another proxy in the chain forwarded back into us, and the event already fired
        // on the way in.
        if depth == 0 {
            let wasTracked = KlaviyoSDK().handleAutomatically(notificationResponse: response)
            if wasTracked && response.actionIdentifier != UNNotificationDismissActionIdentifier {
                markAsAutoTracked(dedupKey: response.klaviyoDedupKey)
            }
        }
        let selector = #selector(
            UNUserNotificationCenterDelegate.userNotificationCenter(
                _:didReceive:withCompletionHandler:
            )
        )
        guard let next = delegate(atDepth: depth, respondingTo: selector) else {
            once()
            return
        }
        next.userNotificationCenter?(
            center, didReceive: response, withCompletionHandler: { once() }
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable
        (UNNotificationPresentationOptions) -> Void
    ) {
        let requestId = notification.request.identifier
        let once = OnceCallback(completionHandler)
        let depth = willPresentGuard.enter(requestId)
        defer { willPresentGuard.leave(requestId) }

        let selector = #selector(
            UNUserNotificationCenterDelegate.userNotificationCenter(
                _:willPresent:withCompletionHandler:
            )
        )
        guard let next = delegate(atDepth: depth, respondingTo: selector) else {
            once(Self.defaultPresentationOptions)
            return
        }
        next.userNotificationCenter?(
            center, willPresent: notification, withCompletionHandler: { once($0) }
        )
    }
}
