//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//

import AnyCodable
import Foundation
#if SWIFT_PACKAGE
import KlaviyoAutomaticPushBootstrap
#endif
import KlaviyoCore
import OSLog
import UIKit

/// Funnels SDK entry-point work onto the main queue, ensuring all orchestration work is serialised
/// on the main queue (FIFO) so call ordering is deterministic.
func dispatchOnMainThread(_ work: @escaping () -> Void) {
    DispatchQueue.main.async {
        work()
    }
}

/// Orders automatic APNs callbacks across the short-lived `KlaviyoSDK` values created by the
/// app-delegate hook. Notification-settings reads are asynchronous and may finish out of order;
/// only the generation belonging to the newest callback is allowed to dispatch its token.
final class AutomaticPushTokenSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var latestGeneration: UInt64 = 0

    func claimGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        latestGeneration &+= 1
        return latestGeneration
    }

    func performIfLatest(_ generation: UInt64, operation: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard generation == latestGeneration else { return }
        operation()
    }
}

/// The main interface for the Klaviyo SDK.
///
/// `KlaviyoSDK` is a lightweight value type. All instances share the same underlying SDK state,
/// so you can create one wherever you need it rather than storing a reference.
///
/// Initialize the SDK with your public API key as early as possible, typically in
/// `application(_:didFinishLaunchingWithOptions:)`:
///
/// ```swift
/// import KlaviyoSwift
///
/// func application(
///     _ application: UIApplication,
///     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
/// ) -> Bool {
///     KlaviyoSDK().initialize(with: "YOUR_PUBLIC_API_KEY")
///     return true
/// }
/// ```
///
/// Then identify the profile, track events, and register for push notifications:
///
/// ```swift
/// KlaviyoSDK()
///     .set(email: "jane@example.com")
///     .set(externalId: "user-123")
///
/// KlaviyoSDK().create(event: Event(name: .viewedProductMetric, properties: ["SKU": "123"]))
/// ```
///
/// Most methods return immediately and apply their change asynchronously on the main queue, in
/// the order they were called.
///
/// ## Topics
///
/// ### Initializing the SDK
///
/// - ``init()``
/// - ``initialize(with:)``
///
/// ### Identifying the Profile
///
/// - ``set(profile:)``
/// - ``set(email:)``
/// - ``set(phoneNumber:)``
/// - ``set(externalId:)``
/// - ``set(profileAttribute:value:)``
/// - ``resetProfile()``
/// - ``email``
/// - ``phoneNumber``
/// - ``externalId``
///
/// ### Tracking Events
///
/// - ``create(event:)``
///
/// ### Subscribing to Lists
///
/// - ``create(subscription:)``
///
/// ### Push Notifications
///
/// - ``set(pushToken:)-(Data)``
/// - ``set(pushToken:)-(String)``
/// - ``pushToken``
/// - ``handle(notificationResponse:withCompletionHandler:)``
/// - ``setBadgeCount(_:)``
///
/// ### Deep Links
///
/// - ``registerDeepLinkHandler(_:)``
/// - ``unregisterDeepLinkHandler()``
/// - ``isDeepLinkHandlerRegistered``
/// - ``handleUniversalTrackingLink(_:)``
///
/// ### Authenticated In-App Forms
///
/// - ``registerAuthTokenProvider(_:)``
/// - ``unregisterAuthTokenProvider()``
///
/// ### Logging
///
/// - ``setLoggingEnabled(_:)``
/// - ``isLoggingEnabled``
///
/// ### Deprecated
///
/// - ``handle(notificationResponse:withCompletionHandler:deepLinkHandler:)``
public struct KlaviyoSDK {
    private static let registerEventDispatcher: Void = EventDispatcher.shared.register(KlaviyoEventDispatcher())
    private static let automaticPushTokenSequence = AutomaticPushTokenSequence()

    /// Creates a handle to the shared Klaviyo SDK.
    ///
    /// Creating an instance doesn't initialize the SDK. Call ``initialize(with:)`` once at launch
    /// before using the other methods.
    public init() {
        _ = Self.registerEventDispatcher
    }

    /// The current profile's email address, or `nil` if none is set.
    public var email: String? {
        IdentityStore.shared.current.email
    }

    /// The current profile's phone number, or `nil` if none is set.
    public var phoneNumber: String? {
        IdentityStore.shared.current.phoneNumber
    }

    /// The current profile's external ID, or `nil` if none is set.
    public var externalId: String? {
        IdentityStore.shared.current.externalId
    }

    /// The APNs device token registered with Klaviyo, as a hexadecimal string, or `nil` if none is set.
    public var pushToken: String? {
        IdentityStore.shared.pushToken?.pushToken
    }

    /// Whether logging is currently enabled for the Klaviyo SDK.
    ///
    /// Logging is enabled by default. When disabled, all `os.Logger` output,
    /// legacy `LoggerClient` error logging, and runtime warnings are silenced.
    public var isLoggingEnabled: Bool {
        KlaviyoLogConfig.shared.isLoggingEnabled
    }

    /// Enable or disable logging for the Klaviyo SDK.
    ///
    /// When disabled, all log output across KlaviyoCore, KlaviyoSwift,
    /// KlaviyoForms, and KlaviyoLocation is silenced. Re-enabling restores
    /// logging immediately.
    ///
    /// - Note: This setting does not affect `KlaviyoSwiftExtension`, which runs
    ///   in a separate app-extension process where this in-memory toggle does
    ///   not apply.
    /// - Parameter enabled: Pass `true` to enable logging, `false` to disable.
    /// - Returns: The current `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func setLoggingEnabled(_ enabled: Bool) -> KlaviyoSDK {
        KlaviyoLogConfig.shared.isLoggingEnabled = enabled
        return self
    }

    /// Initializes the SDK with your Klaviyo public API key.
    ///
    /// Call this once, as early as possible in your app's launch, typically from
    /// `application(_:didFinishLaunchingWithOptions:)`:
    ///
    /// ```swift
    /// KlaviyoSDK().initialize(with: "YOUR_PUBLIC_API_KEY")
    /// ```
    ///
    /// Initialization restores the profile and push token persisted from previous launches, sends
    /// any push token that was set before initialization, and starts sending queued requests.
    /// Calls made before initialization that change the profile, such as ``set(email:)`` or
    /// ``set(profile:)``, are dropped with a warning, so initialize first.
    ///
    /// Calling this again with the same key does nothing. Calling it with a different key switches
    /// to that Klaviyo account: the push token is unregistered from the previous account and
    /// registered with the new one.
    ///
    /// - Parameter apiKey: Your public API key (site ID), from your Klaviyo account settings.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func initialize(with apiKey: String) -> KlaviyoSDK {
        KlaviyoAutomaticPushBootstrapLinkerAnchor()
        dispatchOnMainThread { KlaviyoCommands.initialize(apiKey) }
        klaviyoSwiftEnvironment.injectNotificationDelegate()
        return self
    }

    /// Identifies the current profile and sends its attributes to Klaviyo.
    ///
    /// ```swift
    /// let profile = Profile(
    ///     email: "jane@example.com",
    ///     externalId: "user-123",
    ///     firstName: "Jane",
    ///     properties: ["Plan": "Premium"]
    /// )
    /// KlaviyoSDK().set(profile: profile)
    /// ```
    ///
    /// Later events and requests are attributed to this profile. If a push token is registered, it
    /// moves to this profile.
    ///
    /// If the current profile is already identified and `profile` has a different email, phone
    /// number or external ID, the SDK first starts a new profile, as ``resetProfile()`` does, so two
    /// people are never merged into one Klaviyo profile. If the identifiers are unchanged and
    /// `profile` carries no other attributes, no request is sent.
    ///
    /// - Note: Call ``initialize(with:)`` first. A profile set before initialization is dropped.
    /// - Parameter profile: The profile to identify and send to Klaviyo.
    public func set(profile: Profile) {
        dispatchOnMainThread { KlaviyoCommands.enqueueProfile(profile) }
    }

    /// Clears the current profile's identifiers and starts a new anonymous profile.
    ///
    /// Call this when the user logs out, so later activity isn't attributed to them:
    ///
    /// ```swift
    /// KlaviyoSDK().resetProfile()
    /// ```
    ///
    /// The email, phone number, external ID and any pending profile attributes are cleared. If the
    /// profile was identified, the SDK creates a new anonymous ID. If a push token is registered,
    /// it moves to the new anonymous profile.
    ///
    /// - Note: Call ``initialize(with:)`` first. A reset before initialization is ignored.
    public func resetProfile() {
        dispatchOnMainThread { KlaviyoCommands.resetProfile() }
    }

    /// Sets the app icon's badge number and saves it to the shared App Group.
    ///
    /// The saved count is the one `KlaviyoSwiftExtension` increments when a push notification asks
    /// it to, so set the badge with this method rather than directly to keep the two in sync.
    ///
    /// This method requires an App Group shared by your app and its Notification Service
    /// Extension, named by the `klaviyo_app_group` key in your app's `Info.plist`. Without it, this
    /// method does nothing. You can call it before ``initialize(with:)``.
    ///
    /// When badge autoclearing is on (the default, controlled by the `klaviyo_badge_autoclearing`
    /// `Info.plist` key), the SDK resets the badge to 0 each time the app comes to the foreground.
    ///
    /// - Parameter count: The badge number to show. Pass `0` to clear the badge.
    public func setBadgeCount(_ count: Int) {
        // No initialization gate: setting the badge is a purely local operation
        // (OS badge + app-group UserDefaults) with no dependency on the SDK's API
        // key, profile, or store state. Gating on initialization only created an
        // ordering race with the async `initialize(with:)`, so we apply the badge
        // unconditionally. When no app group is configured this is a no-op.
        Task {
            await BadgeManager.setBadgeCount(count)
        }
    }

    /// Sets the current profile's email address.
    ///
    /// ```swift
    /// KlaviyoSDK().set(email: "jane@example.com")
    /// ```
    ///
    /// Leading and trailing whitespace is trimmed. An empty string, or the email that's already
    /// set, is ignored. To change identifiers on an identified profile and start a separate profile,
    /// use ``set(profile:)`` or call ``resetProfile()`` first.
    ///
    /// - Note: Call ``initialize(with:)`` first. An email set before initialization is dropped.
    /// - Parameter email: The profile's email address.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func set(email: String) -> KlaviyoSDK {
        dispatchOnMainThread { KlaviyoCommands.setEmail(email) }
        return self
    }

    /// Sets the current profile's phone number.
    ///
    /// Use a format Klaviyo accepts, such as E.164 (`+15555550100`). See
    /// [Accepted phone number formats](https://help.klaviyo.com/hc/en-us/articles/360046055671).
    ///
    /// Leading and trailing whitespace is trimmed. An empty string, or the number that's already
    /// set, is ignored.
    ///
    /// - Note: Call ``initialize(with:)`` first. A phone number set before initialization is dropped.
    /// - Parameter phoneNumber: The profile's phone number.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func set(phoneNumber: String) -> KlaviyoSDK {
        dispatchOnMainThread { KlaviyoCommands.setPhoneNumber(phoneNumber) }
        return self
    }

    /// Sets the current profile's external ID.
    ///
    /// An external ID is an identifier from a system outside Klaviyo, such as your backend's user
    /// ID. Read
    /// [Understanding identity resolution](https://help.klaviyo.com/hc/en-us/articles/12902308138011)
    /// before you use it.
    ///
    /// Leading and trailing whitespace is trimmed. An empty string, or the ID that's already set,
    /// is ignored.
    ///
    /// - Note: Call ``initialize(with:)`` first. An external ID set before initialization is dropped.
    /// - Parameter externalId: The profile's external ID.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func set(externalId: String) -> KlaviyoSDK {
        dispatchOnMainThread { KlaviyoCommands.setExternalId(externalId) }
        return self
    }

    /// Sets a single attribute on the current profile.
    ///
    /// ```swift
    /// KlaviyoSDK()
    ///     .set(profileAttribute: .firstName, value: "Jane")
    ///     .set(profileAttribute: .custom(customKey: "Plan"), value: "Premium")
    /// ```
    ///
    /// The SDK collects attributes and sends them with its next batch of requests, so several calls
    /// in a row are sent together.
    ///
    /// - Note: Call ``initialize(with:)`` first. An attribute set before initialization is dropped.
    /// - Parameters:
    ///   - profileAttribute: The attribute to set. Use ``Profile/ProfileKey/custom(customKey:)`` for
    ///     a custom property.
    ///   - value: The attribute's value. It must be encodable as JSON. ``Profile/ProfileKey/latitude``
    ///     and ``Profile/ProfileKey/longitude`` take a `Double`; the other built-in keys take a
    ///     `String`.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func set(profileAttribute: Profile.ProfileKey, value: Any) -> KlaviyoSDK {
        // This seems tricky to implement with Any - might need to restrict to something equatable, encodable....
        dispatchOnMainThread {
            KlaviyoCommands.setProfileProperty(profileAttribute, AnyEncodable(value))
        }
        return self
    }

    /// Tracks an event for the current profile.
    ///
    /// ```swift
    /// let event = Event(
    ///     name: .addedToCartMetric,
    ///     properties: ["ProductName": "Hoodie", "SKU": "HD-001"],
    ///     value: 59.99,
    ///     valueCurrency: "USD"
    /// )
    /// KlaviyoSDK().create(event: event)
    /// ```
    ///
    /// The event is attributed to the profile that's current when it's sent and queued until the
    /// SDK can send it. Events can also trigger in-app forms configured in your Klaviyo account.
    ///
    /// - Note: Call ``initialize(with:)`` first. Events created before initialization are dropped.
    /// - Parameter event: The event to track.
    public func create(event: Event) {
        dispatchOnMainThread { KlaviyoCommands.enqueueEvent(event) }
    }

    /// Subscribes the current profile to a Klaviyo list and records consent for the email, SMS
    /// and WhatsApp channels.
    ///
    /// ```swift
    /// KlaviyoSDK()
    ///     .set(email: "jane@example.com")
    ///     .create(subscription: .allAvailableMarketing(listId: "LIST_ID"))
    /// ```
    ///
    /// The profile must have the identifiers the requested channels need: an email for EMAIL, and a
    /// phone number for SMS and WhatsApp. If an identifier is missing, or no channel is requested,
    /// the SDK logs a warning and sends nothing.
    ///
    /// Use ``Subscription/allAvailableMarketing(listId:customSource:)`` to grant MARKETING consent on
    /// the channels the profile has identifiers for (email and SMS), or the
    /// ``Subscription/init(listId:channels:customSource:)`` initializer with a ``Subscription/Channels``
    /// value to name specific channels and sub-types.
    ///
    /// - Parameter subscription: A ``Subscription`` with the list ID, the channels to request consent
    ///   for, and an optional `customSource` label.
    public func create(subscription: Subscription) {
        dispatchOnMainThread { KlaviyoCommands.enqueueSubscription(subscription) }
    }

    /// Registers the APNs device token with Klaviyo, so the current profile can receive push
    /// notifications.
    ///
    /// Call this from your app delegate when APNs returns a device token:
    ///
    /// ```swift
    /// func application(
    ///     _ application: UIApplication,
    ///     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    /// ) {
    ///     KlaviyoSDK().set(pushToken: deviceToken)
    /// }
    /// ```
    ///
    /// The SDK also records whether the user has authorized notifications. Setting the token that's
    /// already registered, with unchanged settings, sends nothing. A token set before
    /// ``initialize(with:)`` is held in memory and registered once the SDK is initialized.
    ///
    /// - Parameter pushToken: The device token passed to
    ///   `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public func set(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        set(pushToken: apnDeviceToken)
    }

    /// Registers an APNs device token, already converted to a hexadecimal string, with Klaviyo.
    ///
    /// Use this overload when your app receives the token as a string, for example from another
    /// SDK. Otherwise, pass the `Data` token to ``set(pushToken:)-(Data)``. This overload behaves
    /// the same way.
    ///
    /// - Parameter pushToken: The device token as a hexadecimal string.
    public func set(pushToken: String) {
        Task {
            let enablement = await environment.getNotificationSettings()
            dispatchOnMainThread { KlaviyoCommands.setPushToken(pushToken, enablement) }
        }
    }

    /// Automatic APNs callback path. Kept internal so the public/manual API retains its
    /// initialization contract while startup callbacks can buffer the latest token.
    func setAutomatic(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        let generation = Self.automaticPushTokenSequence.claimGeneration()
        Task {
            let enablement = await environment.getNotificationSettings()
            DispatchQueue.main.async {
                Self.automaticPushTokenSequence.performIfLatest(generation) {
                    KlaviyoCommands.setPushToken(apnDeviceToken, enablement)
                }
            }
        }
    }

    /// Resolves a Klaviyo universal tracking link and opens its destination.
    ///
    /// Call this when your app receives a universal link, and handle the URL yourself if it returns
    /// `false`:
    ///
    /// ```swift
    /// func application(
    ///     _ application: UIApplication,
    ///     continue userActivity: NSUserActivity,
    ///     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    /// ) -> Bool {
    ///     guard let url = userActivity.webpageURL else { return false }
    ///     if KlaviyoSDK().handleUniversalTrackingLink(url) {
    ///         return true
    ///     }
    ///     // Handle your other universal links here.
    ///     return false
    /// }
    /// ```
    ///
    /// The SDK resolves the link in the background, then opens the destination URL with the handler
    /// you registered with ``registerDeepLinkHandler(_:)``. If you haven't registered one, it routes
    /// the destination through your app delegate or scene delegate. If the link can't be resolved,
    /// the SDK records the click so Klaviyo can still count it.
    ///
    /// - Parameter url: The universal link URL your app received.
    /// - Returns: `true` if `url` is a Klaviyo universal tracking link (an `http` or `https` URL whose
    ///   path starts with `/u/`) and the SDK is handling it; otherwise `false`.
    public func handleUniversalTrackingLink(_ url: URL) -> Bool {
        if !url.isUniversalTrackingUrl {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("URL '\(url)' is not a Klaviyo universal tracking URL and will not be handled by the Klaviyo SDK")
            }
            return false
        }

        dispatchOnMainThread { KlaviyoCommands.trackingLinkReceived(url) }
        return true
    }

    /// Registers the closure the SDK calls to open deep links from Klaviyo push notifications, in-app
    /// forms and tracking links.
    ///
    /// Register a handler at launch so your app routes Klaviyo deep links itself:
    ///
    /// ```swift
    /// KlaviyoSDK().registerDeepLinkHandler { url in
    ///     router.open(url)
    /// }
    /// ```
    ///
    /// Without a handler, the SDK tries your app delegate's or scene delegate's universal link
    /// handling for `http` and `https` URLs, then falls back to `UIApplication.open(_:)`. External
    /// web URLs that a notification or button marks to open outside the app bypass this handler.
    /// Registering again replaces the previous handler.
    ///
    /// - Parameter handler: A closure that opens the deep link. The SDK calls it on the main thread.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func registerDeepLinkHandler(_ handler: @escaping (URL) -> Void) -> KlaviyoSDK {
        environment.linkHandler.registerCustomHandler(handler)
        return self
    }

    /// Removes the deep link handler registered with ``registerDeepLinkHandler(_:)``.
    ///
    /// The SDK then opens deep links with its fallback behavior, described in
    /// ``registerDeepLinkHandler(_:)``.
    ///
    /// - Note: We recommend keeping a deep link handler registered, so your app controls how Klaviyo
    ///   deep links open.
    /// - Returns: The `KlaviyoSDK` instance, for chaining.
    @discardableResult
    public func unregisterDeepLinkHandler() -> KlaviyoSDK {
        environment.linkHandler.unregisterCustomHandler()
        return self
    }

    /// Whether a deep link handler is registered with ``registerDeepLinkHandler(_:)``.
    public var isDeepLinkHandlerRegistered: Bool {
        environment.linkHandler.hasCustomHandler
    }

    /// Tracks the user's response to a Klaviyo push notification and opens its link.
    ///
    /// Call this from your `UNUserNotificationCenterDelegate`, and call the completion handler
    /// yourself when it returns `false`:
    ///
    /// ```swift
    /// func userNotificationCenter(
    ///     _ center: UNUserNotificationCenter,
    ///     didReceive response: UNNotificationResponse,
    ///     withCompletionHandler completionHandler: @escaping () -> Void
    /// ) {
    ///     let handled = KlaviyoSDK().handle(
    ///         notificationResponse: response,
    ///         withCompletionHandler: completionHandler
    ///     )
    ///     if !handled {
    ///         // Not a Klaviyo notification; handle it yourself.
    ///         completionHandler()
    ///     }
    /// }
    /// ```
    ///
    /// For a Klaviyo notification, the SDK:
    ///
    /// - Tracks an `$opened_push` event, including the button's label, ID and action when the user
    ///   tapped an action button.
    /// - Opens the notification's or button's link. Deep links go to the handler registered with
    ///   ``registerDeepLinkHandler(_:)``; web links marked to open externally open in the browser.
    /// - Does nothing more if the user dismissed the notification, or if the SDK already handled
    ///   this response through automatic push open tracking.
    ///
    /// For any other notification, it returns `false` without calling `completionHandler`.
    ///
    /// - Parameters:
    ///   - notificationResponse: The response passed to
    ///     `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    ///   - completionHandler: The completion handler passed to the same method. For a Klaviyo
    ///     notification, the SDK calls it on the main thread once it has handled the response.
    /// - Returns: `true` if the notification came from Klaviyo and the SDK handled it; otherwise
    ///   `false`.
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        guard notificationResponse.isKlaviyoNotification,
              let properties = notificationResponse.klaviyoProperties else {
            Task { @MainActor in BadgeManager.syncBadgeCount() }
            return false
        }

        if shortCircuitIfAutoTracked(notificationResponse, completionHandler: completionHandler) {
            return true
        }

        defer {
            let categoryIdentifier = notificationResponse.notification.request.content.categoryIdentifier
            klaviyoSwiftEnvironment.pruneCategory(categoryIdentifier)
        }

        // Prune the category if the push with action buttons was dismissed from the Notification Center
        guard notificationResponse.actionIdentifier != UNNotificationDismissActionIdentifier else {
            Task { @MainActor in completionHandler() }
            return true
        }

        // Detect if this is an action button tap
        if notificationResponse.isActionButtonTap {
            handleActionButtonTap(notificationResponse: notificationResponse, properties: properties)
        } else {
            // Regular notification body tap
            create(event: Event(name: ._openedPush, properties: properties, priority: .high))
            resolveOpenAction(for: notificationResponse, deepLinkHandler: nil)
        }

        Task { @MainActor in
            completionHandler()
        }
        return true
    }

    /// Automatic proxy path that performs the same analytics and open action without taking
    /// ownership of the system completion handler forwarded to the host delegate.
    func handleAutomatically(notificationResponse: UNNotificationResponse) -> Bool {
        handle(notificationResponse: notificationResponse, withCompletionHandler: {})
    }

    /// Tracks the user's response to a Klaviyo push notification, passing the notification's deep
    /// link to a closure.
    ///
    /// This behaves like ``handle(notificationResponse:withCompletionHandler:)``, except that a deep
    /// link in the notification body goes to `deepLinkHandler` instead of the handler registered
    /// with ``registerDeepLinkHandler(_:)``. Action-button links and external web URLs don't use
    /// `deepLinkHandler`.
    ///
    /// - Parameters:
    ///   - notificationResponse: The response passed to
    ///     `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    ///   - completionHandler: The completion handler passed to the same method. For a Klaviyo
    ///     notification, the SDK calls it on the main thread once it has handled the response.
    ///   - deepLinkHandler: A closure the SDK calls on the main thread with the deep link in the
    ///     notification body. Pass `nil` to use the registered deep link handler.
    /// - Returns: `true` if the notification came from Klaviyo and the SDK handled it; otherwise
    ///   `false`.
    @available(*, deprecated, message: "This will be removed in v6.0; use `handle(notificationResponse:withCompletionHandler:)` instead")
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void, deepLinkHandler: ((URL) -> Void)? = nil) -> Bool {
        guard notificationResponse.isKlaviyoNotification,
              let properties = notificationResponse.klaviyoProperties else {
            Task { @MainActor in BadgeManager.syncBadgeCount() }
            return false
        }

        if shortCircuitIfAutoTracked(notificationResponse, completionHandler: completionHandler) {
            return true
        }

        defer {
            let categoryIdentifier = notificationResponse.notification.request.content.categoryIdentifier
            klaviyoSwiftEnvironment.pruneCategory(categoryIdentifier)
        }

        // Prune the category if the push with action buttons was dismissed from the Notification Center
        guard notificationResponse.actionIdentifier != UNNotificationDismissActionIdentifier else {
            Task { @MainActor in completionHandler() }
            return true
        }

        if notificationResponse.isActionButtonTap {
            handleActionButtonTap(notificationResponse: notificationResponse, properties: properties)
        } else {
            create(event: Event(name: ._openedPush, properties: properties, priority: .high))
            resolveOpenAction(for: notificationResponse, deepLinkHandler: deepLinkHandler)
        }
        Task { @MainActor in
            completionHandler()
        }
        return true
    }

    /// Returns `true` and fires the completion handler when the Klaviyo proxy delegate has
    /// already auto-tracked this response. The proxy calls `handle(...)` and marks the
    /// request ID before forwarding to any host delegate — a subsequent host call for the
    /// same response would emit a duplicate `Opened Push`.
    private func shortCircuitIfAutoTracked(
        _ notificationResponse: UNNotificationResponse,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        let dedupKey = notificationResponse.klaviyoDedupKey
        guard KlaviyoNotificationDelegate.shared.wasAutoTracked(dedupKey: dedupKey) else {
            return false
        }
        Task { @MainActor in completionHandler() }
        return true
    }

    /// Resolves the open action for a body tap: deep link, web URL, or neither.
    ///
    /// Deep link wins when both are present. The composer enforces a single action
    /// type at creation, so this only matters for direct-API or test-tooling sends.
    ///
    /// When `deepLinkHandler` is non-nil, the deep link is delivered to that closure
    /// instead of being routed through `DeepLinkManager`. External web URLs always
    /// route through `DeepLinkManager.openExternalURL` and intentionally bypass the closure.
    private func resolveOpenAction(
        for notificationResponse: UNNotificationResponse,
        deepLinkHandler: ((URL) -> Void)?
    ) {
        if let deepLinkURL = notificationResponse.klaviyoDeepLinkURL {
            if notificationResponse.klaviyoWebUrl != nil, #available(iOS 14.0, *) {
                Logger.notifications.warning(
                    "Both url and web_url are present; url (deep link) takes precedence and web_url is ignored."
                )
            }
            if let deepLinkHandler = deepLinkHandler {
                Task { @MainActor in
                    deepLinkHandler(deepLinkURL)
                }
            } else {
                Task { @MainActor in await DeepLinkManager.openDeepLink(deepLinkURL) }
            }
        } else if let webUrl = notificationResponse.klaviyoWebUrl {
            Task { @MainActor in await DeepLinkManager.openExternalURL(webUrl) }
        }
    }

    /// Handles action button tap events.
    ///
    /// This method:
    /// - Tracks a `$opened_push` event with button properties (Button Label, Button Action, Button Link)
    /// - Handles action-specific deep links or `open_url` external URLs (or falls back to default
    ///   notification URL)
    ///
    /// - Parameters:
    ///   - notificationResponse: The notification response containing action info
    ///   - properties: The Klaviyo notification properties
    private func handleActionButtonTap(
        notificationResponse: UNNotificationResponse,
        properties: [String: Any]
    ) {
        // Create event properties with action metadata
        var actionProperties = properties
        if let label = notificationResponse.actionButtonLabel {
            actionProperties["Button Label"] = label
        }

        if let buttonId = notificationResponse.actionButtonId {
            actionProperties["Button ID"] = buttonId
        }

        if let actionType = notificationResponse.actionButtonType {
            actionProperties["Button Action"] = actionType.displayName()
        }

        if let url = notificationResponse.actionButtonURL {
            switch notificationResponse.actionButtonType {
            case .deepLink:
                actionProperties["Button Link"] = url.absoluteString
                Task { @MainActor in await DeepLinkManager.openDeepLink(url) }
            case .openUrl:
                actionProperties["Button Link"] = url.absoluteString
                guard url.hasAllowedOpenUrlScheme else {
                    if #available(iOS 14.0, *) {
                        Logger.notifications.warning(
                            "Action button open_url scheme not in the allowed list; ignoring."
                        )
                    }
                    break
                }
                Task { @MainActor in await DeepLinkManager.openExternalURL(url) }
            case .openApp, .none:
                break
            }
        }

        // Track action button event
        create(event: Event(name: ._openedPush, properties: actionProperties, priority: .high))
    }
}

extension KlaviyoSDK: KlaviyoSDKModule {}

// MARK: - Private Helpers

extension URL {
    /// Determines whether the provided URL is a Klaviyo universal tracking URL.
    fileprivate var isUniversalTrackingUrl: Bool {
        ["http", "https"].contains(scheme?.lowercased()) && path.hasPrefix("/u/")
    }
}
