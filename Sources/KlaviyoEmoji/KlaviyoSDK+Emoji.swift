import Foundation
import KlaviyoForms
import KlaviyoSwift
import UserNotifications

// MARK: - KlaviyoSDK emoji methods

extension KlaviyoSDK {
    // MARK: Properties

    /// The current user's email. Equivalent to ``KlaviyoSDK/email``.
    public var 📧: String? { email }

    /// The current user's phone number. Equivalent to ``KlaviyoSDK/phoneNumber``.
    public var 📞: String? { phoneNumber }

    /// The current user's external ID. Equivalent to ``KlaviyoSDK/externalId``.
    public var 🪪: String? { externalId }

    /// The current user's push token. Equivalent to ``KlaviyoSDK/pushToken``.
    public var 🔔: String? { pushToken }

    /// Whether a custom deep link handler is registered. Equivalent to ``KlaviyoSDK/isDeepLinkHandlerRegistered``.
    public var 🪝: Bool { isDeepLinkHandlerRegistered }

    // MARK: Setup

    /// Initialize the SDK with an API key. Equivalent to ``KlaviyoSDK/initialize(with:)``.
    @discardableResult
    public func 🚀(with apiKey: String) -> 😂 {
        initialize(with: apiKey)
    }

    // MARK: Profile

    /// Set a profile. Equivalent to ``KlaviyoSDK/set(profile:)``.
    public func 👤(_ profile: Profile) {
        set(profile: profile)
    }

    /// Set the current user's email. Equivalent to ``KlaviyoSDK/set(email:)``.
    @discardableResult
    public func 📧(_ email: String) -> 😂 {
        set(email: email)
    }

    /// Set the current user's phone number. Equivalent to ``KlaviyoSDK/set(phoneNumber:)``.
    @discardableResult
    public func 📞(_ phoneNumber: String) -> 😂 {
        set(phoneNumber: phoneNumber)
    }

    /// Set the current user's external ID. Equivalent to ``KlaviyoSDK/set(externalId:)``.
    @discardableResult
    public func 🪪(_ externalId: String) -> 😂 {
        set(externalId: externalId)
    }

    /// Set a profile attribute. Equivalent to ``KlaviyoSDK/set(profileAttribute:value:)``.
    @discardableResult
    public func 🏷️(_ attribute: Profile.ProfileKey, _ value: Any) -> 😂 {
        set(profileAttribute: attribute, value: value)
    }

    /// Reset the current profile. Equivalent to ``KlaviyoSDK/resetProfile()``.
    public func 🔄() {
        resetProfile()
    }

    // MARK: Events

    /// Track an event. Equivalent to ``KlaviyoSDK/create(event:)``.
    public func 📊(_ event: Event) {
        create(event: event)
    }

    // MARK: Push

    /// Set the push token from raw data. Equivalent to ``KlaviyoSDK/set(pushToken:)-7r3k2``.
    public func 🔔(_ pushToken: Data) {
        set(pushToken: pushToken)
    }

    /// Set the push token from a string. Equivalent to ``KlaviyoSDK/set(pushToken:)-2mktu``.
    public func 🔔(_ pushToken: String) {
        set(pushToken: pushToken)
    }

    /// Set the app badge count. Equivalent to ``KlaviyoSDK/setBadgeCount(_:)``.
    public func 🔢(_ count: Int) {
        setBadgeCount(count)
    }

    /// Handle a notification response. Equivalent to ``KlaviyoSDK/handle(notificationResponse:withCompletionHandler:)``.
    @discardableResult
    public func 🔕(_ response: UNNotificationResponse, _ completionHandler: @escaping () -> Void) -> Bool {
        handle(notificationResponse: response, withCompletionHandler: completionHandler)
    }

    // MARK: Links

    /// Handle a Klaviyo universal tracking link. Equivalent to ``KlaviyoSDK/handleUniversalTrackingLink(_:)``.
    @discardableResult
    public func 🔗(_ url: URL) -> Bool {
        handleUniversalTrackingLink(url)
    }

    /// Register a deep link handler. Equivalent to ``KlaviyoSDK/registerDeepLinkHandler(_:)``.
    @discardableResult
    public func 🪝(_ handler: @escaping (URL) -> Void) -> 😂 {
        registerDeepLinkHandler(handler)
    }

    /// Unregister the deep link handler. Equivalent to ``KlaviyoSDK/unregisterDeepLinkHandler()``.
    @discardableResult
    public func 🪝🗑️() -> 😂 {
        unregisterDeepLinkHandler()
    }

    // MARK: In-App Forms

    /// Register for in-app forms. Equivalent to ``KlaviyoSDK/registerForInAppForms(configuration:)``.
    @MainActor
    public func 📲(_ configuration: InAppFormsConfig = InAppFormsConfig()) {
        registerForInAppForms(configuration: configuration)
    }

    /// Unregister from in-app forms. Equivalent to ``KlaviyoSDK/unregisterFromInAppForms()``.
    @MainActor
    public func 📴() {
        unregisterFromInAppForms()
    }
}
