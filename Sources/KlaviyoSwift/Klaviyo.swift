//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//

import Combine
import Foundation
import KlaviyoCore
import KlaviyoSDKDependencies
import UIKit

func dispatchStoreAction(action: KlaviyoAction) async {
    _ = await klaviyoSwiftEnvironment.send(action)
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
#if swift(<5.10)
@MainActor(unsafe)
#else
@preconcurrency@MainActor
#endif
public struct KlaviyoSDK {
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
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .initialize(apiKey, appContextInfo))
        }
        return self
    }

    /// Set a profile in your Klaviyo account.
    /// Future SDK calls will use this data when making api requests to Klaviyo.
    /// NOTE: this will move any set push tokens over to this profile.
    /// NOTE: this will trigger a reset of existing profile see ``resetProfile()`` for details.
    /// - Parameter profile: a profile object to send to Klaviyo
    public func set(profile: Profile) {
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .enqueueProfile(profile, appContextInfo))
        }
    }

    /// Clears all stored profile identifiers (e.g. email or phone) and starts a new tracked profile.
    /// NOTE: if a push token was registered to the current profile, Klaviyo will disassociate it
    /// from the current profile. Existing token data will be associated with a new anonymous profile.
    /// This should be called whenever an active user in your app is removed (e.g. after a logout).
    public func resetProfile() {
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .resetProfile(appContextInfo))
        }
    }

    /// Sets the badge number on the application icon. Syncs with the persisted count
    /// stored in the User Defaults suite set up with the App Group. Used to set the badge count
    /// to 0 when autoclearing is turned on (in the plist). Can be called otherwise as well.
    public func setBadgeCount(_ count: Int) {
        Task {
            await dispatchStoreAction(action: .setBadgeCount(count))
        }
    }

    /// Set the current user's email.
    /// - Parameter email: a string contining the users email.
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(email: String) -> KlaviyoSDK {
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .setEmail(email, appContextInfo))
        }
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
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .setPhoneNumber(phoneNumber, appContextInfo))
        }
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
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .setExternalId(externalId, appContextInfo))
        }
        return self
    }

    /// Set a profile property on the current user's propfile.
    /// - Parameter profileAttribute: a profile attribute key to be set on the user's profile.
    /// - Parameter value: any encodable value profile property value.
    /// - Returns: a KlaviyoSDK instance
    @discardableResult
    public func set(profileAttribute: Profile.ProfileKey, value: Any) -> KlaviyoSDK {
        // This seems tricky to implement with Any - might need to restrict to something equatable, encodable....
        Task {
            await dispatchStoreAction(action: .setProfileProperty(profileAttribute, AnyEncodable(value)))
        }
        return self
    }

    /// Create and send an event for the current user.
    /// - Parameter event: the event to be tracked in Klaviyo
    public func create(event: Event) {
        Task {
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .enqueueEvent(event, appContextInfo))
        }
    }

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notificaitons.
    /// - Parameter pushToken: data object containing a push token.
    public func set(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        set(pushToken: apnDeviceToken)
    }

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notificaitons.
    /// - Parameter pushToken: String formatted push token.
    public func set(pushToken: String) {
        Task {
            let enablement = await environment.getNotificationSettings()
            let background = klaviyoSwiftEnvironment.getBackgroundSetting()
            let appContextInfo = environment.appContextInfo()
            await dispatchStoreAction(action: .setPushToken(pushToken, enablement, background, appContextInfo))
        }
    }

    /// Track a notificationResponse open event in Klaviyo. NOTE: all callbacks will be made on the main thread.
    /// - Parameters:
    ///   - remoteNotification: the remote notificaiton that was opened
    ///   - completionHandler: a completion handler that will be called with a result for Klaviyo notifications
    ///   - deepLinkHandler: a completion handler that will be called when a notification contains a deep link.
    /// - Returns: true if the notificaiton originated from Klaviyo, false otherwise.
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void, deepLinkHandler: ((URL) -> Void)? = nil) -> Bool {
        if let properties = notificationResponse.notification.request.content.userInfo as? [String: Any],
           let body = properties["body"] as? [String: Any], let _ = body["_k"] {
            create(event: Event(name: ._openedPush, properties: properties))
            if let url = properties["url"] as? String, let url = URL(string: url) {
                if let deepLinkHandler = deepLinkHandler {
                    deepLinkHandler(url)
                } else {
                    Task {
                        await MainActor.run {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            completionHandler()
            return true
        }
        Task {
            await dispatchStoreAction(action: .syncBadgeCount)
        }
        return false
    }
}
