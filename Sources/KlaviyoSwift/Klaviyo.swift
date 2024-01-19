//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//

import AnyCodable
import Foundation
import UIKit

func dispatchOnMainThread(action: KlaviyoAction) {
    Task {
        await MainActor.run {
            environment.analytics.send(action)
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
        environment.analytics.state()
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
    /// - Parameter phonNumber: a string contining the users phone number.
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

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notificaitons.
    /// - Parameter pushToken: data object containing a push token.
    public func set(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        set(pushToken: apnDeviceToken)
    }

    /// Set the current user's push token. This will be associated with profile and can be used to send them push notificaitons.
    /// - Parameter pushToken: String formatted push token.
    public func set(pushToken: String) {
        environment.getNotificationSettings { enablement in
            dispatchOnMainThread(action: .setPushToken(
                pushToken,
                enablement))
        }
    }

    /// Track a notificationResponse open event in Klaviyo. NOTE: all callbacks will be made on the main thread.
    /// - Parameters:
    ///   - remoteNotification: the remote notificaiton that was opened
    ///   - completionHandler: a completion handler that will be called with a result for Klaviyo notifications
    ///   - deepLinkHandler: a completion handler that will be called when a notification contains a deep link.
    /// - Returns: true if the notificaiton originated from Klaviyo, false otherwise.
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void, deepLinkHandler: ((URL) -> Void)? = nil) -> Bool {
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        create(event: Event(name: .CustomEvent("in handle push notification")))
//        }

//        sendEvent()
        completionHandler()
        return true
    }

    private func sendEvent() {
        // Create a URL
        if let url = URL(string: "https://a.klaviyo.com/client/events/?company_id=Xr5bFG") {
            // Create a URLRequest with the specified URL
            var request = URLRequest(url: url)

            // Set the HTTP method to POST
            request.httpMethod = "POST"

            request.setValue("2023-10-15", forHTTPHeaderField: "revision")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            // Set the request body (if needed)
            let requestBody = """
            {
              "data": {
                "type": "event",
                "attributes": {
                  "properties": {
                 "action": "Reset Password"
                },
                  "metric": {
                    "data": {
                      "type": "metric",
                      "attributes": {
                        "name": "Reset Password"
                      }
                    }
                  },
                  "profile": {
                    "data": {
                      "type": "profile",
                      "attributes": {
                        "email": "sarah.mason@klaviyo-demo.com"
                      },
                      "properties":{
                      "PasswordResetLink": "https://www.website.com/reset/1234567890987654321"
                      }
                    }
                  },
                "unique_id": "4b5d3f33-2e21-4c1c-b392-2dae2a74a2ed"
                }
              }
            }
            """
            request.httpBody = requestBody.data(using: .utf8)

            // Create a URLSession instance
            let session = URLSession.shared

            // Create a data task
            let task = session.dataTask(with: request) { data, _, error in

                // Check for errors
                if let error = error {
                    print("Error: \(error)")
                    return
                }

                // Check if there is data
                guard let responseData = data else {
                    print("No data received")
                    return
                }

                // Parse the data (if needed)
                do {
                    let json = try JSONSerialization.jsonObject(with: responseData, options: [])
                    print("JSON Response: \(json)")
                } catch {
                    print("Error parsing JSON: \(error)")
                }
            }

            // Resume the task
            task.resume()
        } else {
            print("Invalid URL")
        }
    }

//    public func handle(userInfo: [AnyHashable: Any], deepLinkHandler: ((URL) -> Void)? = nil) -> Bool {
//        create(event: Event(name: .CustomEvent("user info"), properties: userInfo as? [String: Any]))
//        if let properties = userInfo as? [String: Any],
//           let body = properties["body"] as? [String: Any], let _ = body["_k"] {
//            create(event: Event(name: .OpenedPush, properties: properties))
//            Task {
//                await MainActor.run {
//                    if let url = properties["url"] as? String, let url = URL(string: url) {
//                        if let deepLinkHandler = deepLinkHandler {
//                            deepLinkHandler(url)
//                        } else {
//                            UIApplication.shared.open(url)
//                        }
//                    }
//                }
//            }
//
//            return true
//        }
//        return false
//    }
}
