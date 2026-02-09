//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//

import AnyCodable
import Foundation
import KlaviyoCore
import OSLog
import UIKit

func dispatchOnMainThread(action: KlaviyoAction) {
    Task {
        await MainActor.run {
            klaviyoSwiftEnvironment.send(action)
        }
    }
}

/// The main interface for the Klaviyo SDK.
/// Create a new instance as follows:
///
/// ```swift
/// let sdk = KlaviyoSDK()
/// sdk.initialize(apiKey: "myapikey")
/// ```
///
/// From there you can you can call the additional methods below to track events and profile.
public struct KlaviyoSDK {
    /// Default initializer for the Klaviyo SDK.
    public init() {}

    private var state: KlaviyoState {
        klaviyoSwiftEnvironment.state()
    }

    /// Returns the email for the current user, if any.
    public var email: String? {
        state.email
    }

    /// Returns the phoneNumber for the current user, if any.
    public var phoneNumber: String? {
        state.phoneNumber
    }

    /// Returns the external id for the current user, if any.
    public var externalId: String? {
        state.externalId
    }

    /// Returns the push token for the current user, if any.
    public var pushToken: String? {
        state.pushTokenData?.pushToken
    }

    /// Initialize the swift SDK with the given api key.
    /// NOTE: if the SDK has been initialized previously this will result in the profile
    /// information being reset and the token data being reassigned (see ``resetProfile()`` for details.)
    /// - Parameter apiKey: your public api key from the Klaviyo console
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func initialize(with apiKey: String) -> KlaviyoSDK {
        dispatchOnMainThread(action: .initialize(apiKey))
        return self
    }

    /// Set a profile in your Klaviyo account.
    /// Future SDK calls will use this data when making api requests to Klaviyo.
    /// NOTE: this will move any set push tokens over to this profile.
    /// NOTE: this will trigger a reset of existing profile see ``resetProfile()`` for details.
    /// - Parameter profile: a profile object to send to Klaviyo
    public func set(profile: Profile) {
        dispatchOnMainThread(action: .enqueueProfile(profile))
    }

    /// Clears all stored profile identifiers (e.g. email or phone) and starts a new tracked profile.
    /// NOTE: if a push token was registered to the current profile, Klaviyo will disassociate it
    /// from the current profile. Existing token data will be associated with a new anonymous profile.
    /// This should be called whenever an active user in your app is removed (e.g. after a logout).
    public func resetProfile() {
        dispatchOnMainThread(action: .resetProfile)
    }

    /// Sets the badge number on the application icon. Syncs with the persisted count
    /// stored in the User Defaults suite set up with the App Group. Used to set the badge count
    /// to 0 when autoclearing is turned on (in the plist). Can be called otherwise as well.
    public func setBadgeCount(_ count: Int) {
        dispatchOnMainThread(action: .setBadgeCount(count))
    }

    /// Set the current user's email.
    /// - Parameter email: a string contining the users email.
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(email: String) -> KlaviyoSDK {
        dispatchOnMainThread(action: .setEmail(email))
        return self
    }

    /// Set the current user's phone number.
    /// NOTE: The phone number should be in a format that Klaviyo accepts.
    /// See https://help.klaviyo.com/hc/en-us/articles/360046055671-Accepted-phone-number-formats-for-SMS-in-Klaviyo
    /// for information on phone numbers Klaviyo accepts.
    /// - Parameter phoneNumber: a string contining the users phone number.
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(phoneNumber: String) -> KlaviyoSDK {
        dispatchOnMainThread(action: .setPhoneNumber(phoneNumber))
        return self
    }

    /// Set the current user's external id.
    /// This could be an id from a system external to Klaviyo, for example your backend's user id.
    /// NOTE: Please consult with https://help.klaviyo.com/hc/en-us/articles/12902308138011-Understanding-identity-resolution-in-Klaviyo-
    /// and familiarize yourself with identity resolution before using this identifier.
    /// - Parameter externalId: a string containing an external id
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(externalId: String) -> KlaviyoSDK {
        dispatchOnMainThread(action: .setExternalId(externalId))
        return self
    }

    /// Set a profile property on the current user's propfile.
    /// - Parameter profileAttribute: a profile attribute key to be set on the user's profile.
    /// - Parameter value: any encodable value profile property value.
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(profileAttribute: Profile.ProfileKey, value: Any) -> KlaviyoSDK {
        // This seems tricky to implement with Any - might need to restrict to something equatable, encodable....
        dispatchOnMainThread(action: .setProfileProperty(profileAttribute, AnyEncodable(value)))
        return self
    }

    /// Create and send an event for the current user.
    /// - Parameter event: the event to be tracked in Klaviyo
    public func create(event: Event) {
        dispatchOnMainThread(action: .enqueueEvent(event))
    }

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notifications.
    /// - Parameter pushToken: data object containing a push token.
    public func set(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        set(pushToken: apnDeviceToken)
    }

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notifications.
    /// - Parameter pushToken: String formatted push token.
    public func set(pushToken: String) {
        Task {
            let enablement = await environment.getNotificationSettings()
            dispatchOnMainThread(action: .setPushToken(pushToken, enablement))
        }
    }

    /// Handles a Klaviyo universal tracking link URL by resolving it to a destination URL asynchronously and invoking the registered Deep Link Handler or invoking the AppDelegate or SceneDelegate's link handling logic.
    ///
    /// - Parameter url: the Klaviyo universal tracking link URL.
    /// - Returns: `true` if the URL is a valid Klaviyo universal tracking link; `false` otherwise.
    public func handleUniversalTrackingLink(_ url: URL) -> Bool {
        if !url.isUniversalTrackingUrl {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("URL '\(url)' is not a Klaviyo universal tracking URL and will not be handled by the Klaviyo SDK")
            }
            return false
        }

        dispatchOnMainThread(action: .trackingLinkReceived(url))
        return true
    }

    /// Register a custom deep link handler to be used by the SDK when opening Klaviyo deep links.
    ///
    /// If set, this handler will be invoked instead of the default URL opener.
    /// - Parameter handler: a closure receiving the deep link `URL` to handle.
    /// - Returns: a KlaviyoSDK instance for chaining.
    @discardableResult
    public func registerDeepLinkHandler(_ handler: @escaping (URL) -> Void) -> KlaviyoSDK {
        environment.linkHandler.registerCustomHandler(handler)
        return self
    }

    /// Unregisters any custom deep link handler that was previously registered, reverting the SDK to using a fallback deep link handler implementation.
    ///
    /// - Note: For stability and future-proofing, we recommend always having a deep link handler registered
    @discardableResult
    public func unregisterDeepLinkHandler() -> KlaviyoSDK {
        environment.linkHandler.unregisterCustomHandler()
        return self
    }

    /// Returns true if a custom deep link handler is currently registered.
    public var isDeepLinkHandlerRegistered: Bool {
        environment.linkHandler.hasCustomHandler
    }

    /// Track a notificationResponse open event in Klaviyo. NOTE: all callbacks will be made on the main thread.
    /// - Parameters:
    ///   - remoteNotification: the remote notification that was opened
    ///   - completionHandler: a completion handler that will be called with a result for Klaviyo notifications
    /// - Returns: true if the notification originated from Klaviyo, false otherwise.
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        guard notificationResponse.isKlaviyoNotification,
              let properties = notificationResponse.klaviyoProperties else {
            dispatchOnMainThread(action: .syncBadgeCount)
            return false
        }

        // Prune the category if the push with action buttons was dismissed from the Notification Center
        guard notificationResponse.actionIdentifier != UNNotificationDismissActionIdentifier else {
            let categoryIdentifier = notificationResponse.notification.request.content.categoryIdentifier
            KlaviyoCategoryManager.shared.pruneCategory(categoryIdentifier: categoryIdentifier)
            return true
        }

        // Detect if this is an action button tap
        if notificationResponse.isActionButtonTap {
            handleActionButtonTap(notificationResponse: notificationResponse, properties: properties)
        } else {
            // Regular notification body tap
            create(event: Event(name: ._openedPush, properties: properties))
            if let url = notificationResponse.klaviyoDeepLinkURL {
                dispatchOnMainThread(action: .openDeepLink(url))
            }
        }

        // Prune the category after all event handling and deep link handling is complete
        let categoryIdentifier = notificationResponse.notification.request.content.categoryIdentifier
        KlaviyoCategoryManager.shared.pruneCategory(categoryIdentifier: categoryIdentifier)

        Task { @MainActor in
            completionHandler()
        }
        return true
    }

    /// Track a notificationResponse open event in Klaviyo. NOTE: all callbacks will be made on the main thread.
    /// - Parameters:
    ///   - remoteNotification: the remote notification that was opened
    ///   - completionHandler: a completion handler that will be called with a result for Klaviyo notifications
    ///   - deepLinkHandler: a completion handler that will be called when a notification contains a deep link.
    /// - Returns: true if the notification originated from Klaviyo, false otherwise.
    @available(*, deprecated, message: "This will be removed in v6.0; use `handle(notificationResponse:withCompletionHandler:)` instead")
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void, deepLinkHandler: ((URL) -> Void)? = nil) -> Bool {
        guard notificationResponse.isKlaviyoNotification,
              let properties = notificationResponse.klaviyoProperties else {
            dispatchOnMainThread(action: .syncBadgeCount)
            return false
        }

        create(event: Event(name: ._openedPush, properties: properties))
        if let url = notificationResponse.klaviyoDeepLinkURL {
            if let deepLinkHandler = deepLinkHandler {
                Task { @MainActor in
                    deepLinkHandler(url)
                }
            } else {
                dispatchOnMainThread(action: .openDeepLink(url))
            }
        }
        Task { @MainActor in
            completionHandler()
        }
        return true
    }

    /// Handles action button tap events.
    ///
    /// This method:
    /// - Tracks a `$opened_push` event with button properties (Button Label, Button Action, Button Link)
    /// - Handles action-specific deep links (or falls back to default notification URL)
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

        if let url = notificationResponse.actionButtonURL, notificationResponse.actionButtonType == .deepLink {
            actionProperties["Button Link"] = url.absoluteString
            dispatchOnMainThread(action: .openDeepLink(url))
        }

        // Track action button event
        create(event: Event(name: ._openedPush, properties: actionProperties))
    }
}

// MARK: - Private Helpers

extension URL {
    /// Determines whether the provided URL is a Klaviyo universal tracking URL.
    fileprivate var isUniversalTrackingUrl: Bool {
        ["http", "https"].contains(scheme?.lowercased()) && path.hasPrefix("/u/")
    }
}
