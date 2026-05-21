//
//  KlaviyoNotificationDelegate.swift
//  klaviyo-swift-sdk
//
//  Created by Glenn Brannelly on 5/13/26.
//

import Foundation
import OSLog
import UserNotifications

/// A proxy `UNUserNotificationCenterDelegate` that the SDK injects at `initialize()` to intercept
/// push notification responses automatically.
///
/// When injected, this delegate:
/// - Tracks push opens for Klaviyo notifications via ``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)``
/// - Forwards all callbacks to the host app's existing delegate
/// - Prevents double-tracking when a developer still has a manual ``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)``
///   call in their own delegate after upgrading the SDK
///
/// ## Concurrency model
///
/// The class is marked `@unchecked Sendable` because the singleton (`shared`) is reached from
/// multiple isolation contexts:
/// - `UNUserNotificationCenter` delivers its delegate callbacks on the main thread by Apple's
///   convention. `existingDelegate`, the KVO observation, and `inject()` are therefore treated
///   as **main-thread-only** state. The KVO closure is registered with `OperationQueue.main`
///   so observations land on main even when the delegate is reassigned from a background
///   thread.
/// - `markAsAutoTracked(requestId:)`, `wasAutoTracked(requestId:)`, and `clearAutoTracked()`
///   are reachable from any thread because `KlaviyoSDK().handle(notificationResponse:)` is a
///   public API. These three accessors serialize all reads/writes to the auto-tracked Set and
///   FIFO queue through `autoTrackedLock`.
final class KlaviyoNotificationDelegate: NSObject, @unchecked Sendable {
    static let shared = KlaviyoNotificationDelegate()

    /// The host app's delegate that was in place before SDK injection (or set afterwards via
    /// KVO). Main-thread-only — written by `inject()` (dispatched on `MainActor`) and the KVO
    /// observation (which runs on `OperationQueue.main`); read by the `UNUserNotificationCenter`
    /// delegate callbacks (delivered on main).
    ///
    /// Reference is `weak` to mirror Apple's own contract: `UNUserNotificationCenter.delegate`
    /// is declared `weak`, so this property must not silently extend the lifetime of the host's
    /// delegate beyond what the host itself retains. The trade-off is that hosts who assigned a
    /// short-lived object as the delegate without keeping a separate strong reference will see
    /// it deallocated as soon as the SDK replaces it as the center's delegate. (Apple's
    /// contract had the same effect — a host that didn't retain its delegate strongly already
    /// had a use-after-deallocation hazard — but the SDK proxy makes the deallocation happen
    /// at a deterministic point.) `inject()` schedules a one-shot post-injection check that
    /// logs a warning if this is detected, so the failure mode is visible in the console
    /// instead of silently losing forwarded UN callbacks.
    weak var existingDelegate: (any UNUserNotificationCenterDelegate)?

    /// Maximum number of recent request identifiers retained for the double-track guard.
    /// UNNotificationRequest identifiers are typically 36-character UUIDs, so 256 entries is
    /// roughly 10 KB — small enough to keep without memory pressure and large enough that the
    /// FIFO eviction here will never displace an identifier before a paired manual `handle()`
    /// call arrives. Tune up only if we see false-positive double-fires in production.
    static let autoTrackedRequestIdCapacity = 256

    /// Request identifiers that have already been auto-tracked to prevent duplicate open
    /// events. Bounded via a FIFO insertion-order queue (`autoTrackedRequestIdOrder`) so the
    /// set can't grow without limit over a long-lived process. All mutation must go through
    /// `markAsAutoTracked(requestId:)` or `clearAutoTracked()` — both serialize writes through
    /// `autoTrackedLock` and keep the set and FIFO queue in sync. `private(set)` enforces the
    /// "no external mutation" contract in the type system; reads remain internal so the test
    /// target can assert on the queue state with `@testable import KlaviyoSwift`.
    private(set) var autoTrackedRequestIds: Set<String> = []

    /// Insertion-order companion to `autoTrackedRequestIds`. The two are mutated together by
    /// `markAsAutoTracked(requestId:)` so the oldest identifier is evicted from both once the
    /// queue exceeds `autoTrackedRequestIdCapacity`.
    private(set) var autoTrackedRequestIdOrder: [String] = []

    /// Serializes access to `autoTrackedRequestIds` and `autoTrackedRequestIdOrder`. The
    /// proxy's `didReceive` callback is delivered on the main thread by convention, but
    /// `KlaviyoSDK().handle(notificationResponse:)` is a public API any host can invoke from
    /// any thread, so we can't rely on main-thread serialization alone.
    private let autoTrackedLock = NSLock()

    /// KVO token kept alive for the lifetime of the SDK. Main-thread-only; written by
    /// `inject()` once at initialize time.
    private var kvoObservation: NSKeyValueObservation?

    /// Request identifiers whose `didReceive` forward is currently in flight. If we re-enter
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)` for an id that's already
    /// in here, our `existingDelegate` chain has looped back into us — almost always because
    /// another push-notification SDK installed its own proxy with our proxy captured as its
    /// "prior" delegate, while we captured its proxy as our `existingDelegate`. Without a
    /// guard, that mutual forwarding recurses until the stack overflows. See the "Scenario 4"
    /// finding documented in the auto-tracking design doc for full discussion.
    private var forwardingDidReceiveIds: Set<String> = []
    private var forwardingWillPresentIds: Set<String> = []
    private let forwardingLock = NSLock()

    private func beginForwardingDidReceive(_ id: String) -> Bool {
        forwardingLock.lock()
        defer { forwardingLock.unlock() }
        return forwardingDidReceiveIds.insert(id).inserted
    }

    private func endForwardingDidReceive(_ id: String) {
        forwardingLock.lock()
        forwardingDidReceiveIds.remove(id)
        forwardingLock.unlock()
    }

    private func beginForwardingWillPresent(_ id: String) -> Bool {
        forwardingLock.lock()
        defer { forwardingLock.unlock() }
        return forwardingWillPresentIds.insert(id).inserted
    }

    private func endForwardingWillPresent(_ id: String) {
        forwardingLock.lock()
        forwardingWillPresentIds.remove(id)
        forwardingLock.unlock()
    }

    // MARK: - Test hooks (internal — used by KlaviyoNotificationDelegateTests)

    func testHook_beginForwardingDidReceive(_ id: String) -> Bool {
        beginForwardingDidReceive(id)
    }

    func testHook_endForwardingDidReceive(_ id: String) {
        endForwardingDidReceive(id)
    }

    func testHook_beginForwardingWillPresent(_ id: String) -> Bool {
        beginForwardingWillPresent(id)
    }

    func testHook_endForwardingWillPresent(_ id: String) {
        endForwardingWillPresent(id)
    }

    // MARK: - Injection

    /// Reads the `klaviyo_automatic_push_tracking` plist key and, when explicitly set to `true`,
    /// injects the SDK as `UNUserNotificationCenter.current().delegate`. A KVO observer is
    /// installed to re-inject whenever the host app reassigns the delegate after init (e.g. in a
    /// SceneDelegate).
    ///
    /// Automatic tracking is **opt-in for now**: hosts that have not set the plist key continue
    /// to use the fully manual integration (host calls `KlaviyoSDK().handle(notificationResponse:)`,
    /// `KlaviyoSDK().set(pushToken:)`, etc.). The default will flip to opt-out in a future major
    /// release.
    @MainActor
    static func injectIfEnabled() {
        guard Bundle.main.object(forInfoDictionaryKey: "klaviyo_automatic_push_tracking") as? Bool == true else {
            if #available(iOS 14.0, *) {
                Logger.notifications.info("Klaviyo automatic push tracking is disabled; set klaviyo_automatic_push_tracking=YES in Info.plist to enable.")
            }
            return
        }
        shared.inject()
        KlaviyoAppDelegateSwizzler.swizzleIfPossible()
    }

    @MainActor
    private func inject() {
        let center = UNUserNotificationCenter.current()
        guard center.delegate !== self else { return }
        let hadPriorDelegate = center.delegate != nil
        existingDelegate = center.delegate
        center.delegate = self

        // Detect the "host didn't retain their delegate strongly" footgun. If the host wrote
        // `center.delegate = SomeObject()` without keeping a separate strong reference, the
        // object will be deallocated as soon as we replace it as the center's delegate (both
        // `center.delegate` and our `existingDelegate` are weak). The check has to run on the
        // next main-runloop tick so ARC has drained any autorelease pool that kept the prior
        // delegate alive across the `center.delegate = self` assignment. Logging the warning
        // here makes the failure visible in the console instead of silently dropping forwarded
        // UN callbacks.
        if hadPriorDelegate {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.existingDelegate == nil else { return }
                if #available(iOS 14.0, *) {
                    Logger.notifications.warning(
                        "Klaviyo proxy: the host's previous UNUserNotificationCenter delegate was deallocated immediately after the Klaviyo proxy was installed. UN callbacks will not forward to it. Retain your delegate strongly (e.g., as a property on AppDelegate) so its lifetime outlives the center's weak `delegate` reference."
                    )
                }
            }
        }

        // KVO closure may be invoked on the thread of whichever code reassigns the delegate,
        // so hop back to MainActor before touching `existingDelegate` or the center. The
        // closure intentionally discards its first parameter and re-fetches the singleton
        // inside `MainActor.assumeIsolated` to avoid capturing a non-`Sendable`
        // `UNUserNotificationCenter` across the isolation boundary.
        kvoObservation = center.observe(\.delegate, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let center = UNUserNotificationCenter.current()
                guard center.delegate !== self else { return }
                self.existingDelegate = center.delegate
                center.delegate = self
            }
        }
    }

    // MARK: - Double-track guard

    func markAsAutoTracked(requestId: String) {
        autoTrackedLock.lock()
        defer { autoTrackedLock.unlock() }
        let (inserted, _) = autoTrackedRequestIds.insert(requestId)
        guard inserted else { return }
        autoTrackedRequestIdOrder.append(requestId)
        if autoTrackedRequestIdOrder.count > Self.autoTrackedRequestIdCapacity {
            let evicted = autoTrackedRequestIdOrder.removeFirst()
            autoTrackedRequestIds.remove(evicted)
        }
    }

    func wasAutoTracked(requestId: String) -> Bool {
        autoTrackedLock.lock()
        defer { autoTrackedLock.unlock() }
        return autoTrackedRequestIds.contains(requestId)
    }

    /// Drops all auto-tracked request identifiers. Intended for tests; production code should
    /// rely on the FIFO eviction in `markAsAutoTracked(requestId:)`.
    func clearAutoTracked() {
        autoTrackedLock.lock()
        defer { autoTrackedLock.unlock() }
        autoTrackedRequestIds.removeAll()
        autoTrackedRequestIdOrder.removeAll()
    }
}

/// Single-shot completion wrapper. The proxy passes the same wrapper to both the SDK's
/// `handle()` call and the existing host delegate's `didReceive` callback, so the user-facing
/// completion handler fires exactly once regardless of which path resolves first. The wrapper
/// is a class with internal locking so it satisfies the `@Sendable` requirement of the
/// `UNUserNotificationCenterDelegate` method signatures under strict-concurrency mode.
///
/// Always invokes the wrapped action on the main actor (via `dispatchOnMainThread`). The
/// completion handler iOS gives us runs `UIApplication` state-restoration bookkeeping
/// internally and throws `NSInternalInconsistencyException("Call must be made on main
/// thread")` if invoked off main. Existing delegates the proxy forwards to (e.g.
/// async-stream-based bridges in RN/Flutter host adapters) frequently complete on a
/// non-main task thread, so we hop back to main here rather than trusting callers.
final class OnceCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let action: @Sendable () -> Void

    init(_ action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func call() {
        lock.lock()
        let shouldFire = !fired
        if shouldFire { fired = true }
        lock.unlock()
        guard shouldFire else { return }
        dispatchOnMainThread(action)
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

        // Re-entrance guard: if our `existingDelegate` chain looped back into us for the same
        // notification (third-party proxy registered us as its prior, while we registered it
        // as our existing), abort the forward so the recursion can't overflow the stack.
        guard beginForwardingDidReceive(requestId) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Klaviyo proxy: forwarding cycle detected on didReceive for request \(requestId); aborting nested forward to break the chain.")
            }
            completionHandler()
            return
        }
        defer { endForwardingDidReceive(requestId) }

        // Deduplicated completion — whichever path calls this first wins; subsequent calls are no-ops.
        let once = OnceCallback(completionHandler)
        let onceCallback: @Sendable () -> Void = { once.call() }

        // Only mark as auto-tracked when handle() confirms it's a Klaviyo notification, so the
        // double-track guard in the manual handle() API doesn't incorrectly suppress non-Klaviyo
        // notifications that the existing delegate also passes through handle().
        let wasKlaviyo = KlaviyoSDK().handle(notificationResponse: response, withCompletionHandler: onceCallback)
        if wasKlaviyo {
            markAsAutoTracked(requestId: requestId)
        }

        if let existing = existingDelegate,
           existing.responds(to: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            existing.userNotificationCenter?(center, didReceive: response, withCompletionHandler: onceCallback)
        } else {
            onceCallback()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let requestId = notification.request.identifier

        // Re-entrance guard. Same rationale as in `didReceive`: a third-party SDK proxy can
        // form a forwarding cycle with ours, which without this guard recurses through
        // `willPresent` until the stack overflows.
        guard beginForwardingWillPresent(requestId) else {
            if #available(iOS 14.0, *) {
                Logger.notifications.warning("Klaviyo proxy: forwarding cycle detected on willPresent for request \(requestId); aborting nested forward to break the chain.")
            }
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner])
            } else {
                completionHandler([.alert])
            }
            return
        }
        defer { endForwardingWillPresent(requestId) }

        if let existing = existingDelegate,
           existing.responds(to: #selector(userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            existing.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            return
        }

        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])
        } else {
            completionHandler([.alert])
        }
    }
}
