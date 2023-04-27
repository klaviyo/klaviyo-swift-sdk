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

// MARK: Objective-C

@available(
    iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use KlaviyoSDK for swift apps and KlaviyoObjc for Objective-C apps.")
@objc
public class Klaviyo: NSObject {
    /*
     Klaviyo Class Constants
     */

    // Create the singleton instance
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public static let sharedInstance = Klaviyo()

    private static let sdkInstance = KlaviyoSDK()

    /*
     Klaviyo JSON Key Constants
     */

    // KL Definitions File: JSON Keys for Tracking Events
    let KLEventTrackTokenJSONKey = "token"
    let KLEventTrackEventJSONKey = "event"
    let KLEventTrackCustomerPropetiesJSONKey = "customer_properties" // must use id or email
    let KLEventTrackingServiceKey = "service"

    // Optional Event Tracking Properties
    let KLEventTrackPropertiesJSONKey = "properties"
    let KLEventTrackTimeJSONKey = "time"
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLEventTrackPurchasePlatform = "platform"

    // KL Definitions File: JSON Keys for Tracking People
    let KLPersonTrackTokenJSONKey = "token"
    let KLPersonPropertiesJSONKey = "properties" // same as customer properties

    // Push Notification Event Tracking
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonReceivedPush = "Received Push"

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonOpenedPush = "$opened_push"

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLMessageDimension = "$message"

    // KL Definitions File: API URL Constants

    let KlaviyoServerTrackEventEndpoint = "/track"
    let KlaviyoServerTrackPersonEndpoint = "/identify"

    let KlaviyoServerURLString = "https://a.klaviyo.com"

    let CustomerPropertiesAppendDictKey = "$append"

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let CustomerPropertiesAPNTokensDictKey = "$ios_tokens" // tokens for push notification
    let KLRegisterAPNDeviceTokenEvent = "KL_ReceiveNotificationsDeviceToken"

    // Track event special info dict keys
    let KLEventIDDictKey = "$event_id" // unique identifier for an event
    let KLEventValueDictKey = "$value" // a numeric value to associate with this special event

    // Track person special info dict keys
    let KLPersonIDDictKey = "$id" // your unique identifier for a person
    private let KLCustomerIDNSDefaults = "$kl_customerID"
    let KLPersonDeviceIDDictKey = "$device_id"
    private let KLTimezone = "Mobile Timezone"

    // Public Info Dictionary Keys
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonEmailDictKey = "$email" // email address
    private let KLEmailNSDefaultsKey = "$kl_email"

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonFirstNameDictKey = "$first_name" // first name

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonLastNameDictKey = "$last_name" // last name

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonPhoneNumberDictKey = "$phone_number" // phone number

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonTitleDictKey = "$title" // title at their business or organization

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonOrganizationDictKey = "$organization" // business or organization they belong to

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonCityDictKey = "$city" // city they live in

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonRegionDictKey = "$region" // region or state they live in

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonCountryDictKey = "$country" // country they live in

    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. See KlaviyoSDK to set profile properties.")
    public let KLPersonZipDictKey = "$zip" // postal code where they live

    /*
     Singleton Initializer. Must be kept private as only one instance can be created.
     */
    override private init() {
        super.init()
    }

    /**
     setupWithPublicAPIKey: sets up the Klaviyo iOS SDK for use in the application. Should be called once upon initial application setup in the AppDelegate didFinishLaunchingWithOptions: Requires an account ID, which can be accessed through Klaviyo.com.

     - Parameter apiKey: string representation of the Klaviyo API Key
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().initialize(apiKey:) instead.")
    @objc
    public class func setupWithPublicAPIKey(apiKey: String) {
        // _ avoids warning from xcode
        Self.sdkInstance.initialize(with: apiKey)
    }

    /**
     setUpUserEmail: Register the current user's email address with Klaivyo. This can also be done via passing a dictionary containing a user's email to trackEvent.

     - Parameter userEmail: the user's email address
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().set(email:) instead.")
    @objc
    public func setUpUserEmail(userEmail: String) {
        Self.sdkInstance.set(email: userEmail)
    }

    /*
     setUpCustomerID: Register the current customer ID and saves it
     If this is called once, there is no need to pass in identifiying dictionaries to tracked events
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().set(externalId:) instead.")
    @objc
    public func setUpCustomerID(id: String) {
        Self.sdkInstance.set(externalId: id)
    }

    /**
     handlePush: Extracts tracking information from received push notification and sends the data to Klaviyo for push-tracking
     analystics. Note: this will automatically open any urls found in push payloads unless a deep link handler is specified.

     - Parameter userInfo: NSDictionary containing the push notification text & metadata
     - Parameter deepLinkHandler: optional completion handler to be called when a link is found in a notification
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().handle(notificationResponse:withCompletionHandler:) instead.")
    @objc
    public func handlePush(userInfo: NSDictionary, deepLinkHandler: ((URL) -> Void)? = nil) {
        if let properties = userInfo as? [String: Any],
           let body = properties["body"] as? [String: Any], let _ = body["_k"] {
            Self.sdkInstance
                .create(event: Event(name: .OpenedPush,
                                     properties: properties,
                                     profile: [:]))
            if let url = properties["url"] as? String, let url = URL(string: url) {
                Task {
                    await MainActor.run {
                        if let deepLinkHandler = deepLinkHandler {
                            deepLinkHandler(url)
                        } else {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    /**
     trackEvent: KL Event tracking for event name only

     - Parameter eventName: name of the event
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().create(event:) instead.")
    @objc
    public func trackEvent(eventName: String?) {
        trackEvent(eventName: eventName, properties: nil)
    }

    /**
     trackEvent: KL Event tracking for event name and customer properties

     - Parameter eventName: name of the event
     - Parameter properties: customerProperties
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().create(event:) instead.")
    @objc
    public func trackEvent(eventName: String?, properties: NSDictionary?) {
        trackEvent(eventName: eventName, customerProperties: nil, properties: properties)
    }

    /**
     trackEvent: KL Event tracking for event name, customer & event properties

     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter properties: dictionary for event info
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().create(event:) instead.")
    @objc
    public func trackEvent(eventName: String?, customerProperties: NSDictionary?, properties: NSDictionary?) {
        trackEvent(event: eventName, customerProperties: customerProperties, propertiesDict: properties, eventDate: nil)
    }

    /**
     trackEvent: KL Event tracking using all possible parameters

     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter propertiesDict: dictionary for event info
     - Parameter eventDate: date of the event
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().create(event:) instead.")
    @objc
    public func trackEvent(event: String?, customerProperties: NSDictionary?, propertiesDict: NSDictionary?, eventDate _: NSDate?) {
        guard let eventName = event, !eventName.isEmpty else {
            environment.logger.error("Track called with nil event name")
            return
        }
        // Check both dictionaries
        let customerPropertiesDict = updatePropertiesDictionary(propDictionary: customerProperties)
        assertPropertyTypes(properties: propertiesDict)
        let legacyEvent = LegacyEvent(eventName: eventName, customerProperties: customerPropertiesDict, properties: propertiesDict ?? [:])
        // _ Avoids xcode warning.
        dispatchOnMainThread(action: .enqueueLegacyEvent(legacyEvent))
    }

    /**
     trackPersonWithInfo: method that creates a Klaviyo person tracking instance that is separate from an event

     - Parameter personInfoDictionary: dictionary of user attributes that you wish to track. These can be special properties provided by Klaviyo, such as KLPersonFirstNameDictKey, or created by the user on the fly.

     - Returns: Void
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().create(profile:) instead.")
    @objc
    public func trackPersonWithInfo(personDictionary: NSDictionary) {
        // No info, return
        if personDictionary.allKeys.isEmpty {
            return
        }

        // Update properties for JSON encoding
        let personInfoDictionary = updatePropertiesDictionary(propDictionary: personDictionary)
        assertPropertyTypes(properties: personInfoDictionary)
        let legacyProfile = LegacyProfile(customerProperties: personDictionary)
        // _ Avoids warning in xcode.
        dispatchOnMainThread(action: .enqueueLegacyProfile(legacyProfile))
    }

    /**
     addPushDeviceToken: Registers Klaviyo with Apple Push Notifications (APN)
     Private function creates a unique identifier for the device and uses it to track the event

     - Parameter deviceToken: token provided by Apple that registers push notifications to the given device
     - Returns: Void
     */
    @available(
        iOS, deprecated: 9999, message: "Deprecated as of version 2.0.0. Use `KlaviyoSDK().set(pushToken:) instead.")
    @objc
    public func addPushDeviceToken(deviceToken: Data) {
        Self.sdkInstance.set(pushToken: deviceToken)
    }

    /**
     updatePropertiesDictionary: Internal function that configures the properties dictionary so that it holds the minimum info needed to track events and users
     - Parameter propertiesDictionary: dictionary of properties passed in for a given event or user. May be nil if no parameters are given.
     - Returns: Void
     */
    internal func updatePropertiesDictionary(propDictionary: NSDictionary?) -> NSDictionary {
        let propertiesDictionary = propDictionary?.mutableCopy() as? NSMutableDictionary ?? NSMutableDictionary()

        // Set the user's timezone: Note if the customer exists this will override their current profile
        // Alternatively, could create a customer mobile timezone property instead using a different key
        let timezone = NSTimeZone.local.identifier
        propertiesDictionary[KLTimezone] = timezone

        return propertiesDictionary
    }

    /**
     assertPropretyTypes: Internal alert function for development purposes. Asserts an error if dictionary types are of incorrect type for JSON encoding. Doesn't return a value but will assert an error during development.

     - Parmeter properties: the dictionary of property values
     - Returns: Void
     */
    private func assertPropertyTypes(properties: NSDictionary?) {
        guard let properties = properties else {
            return
        }

        for (k, _) in properties {
            assert((properties[k]! is NSString) ||
                (properties[k]! is NSNumber) ||
                (properties[k]! is NSNull) ||
                (properties[k]! is NSArray) ||
                (properties[k]! is NSDictionary) ||
                (properties[k]! is NSDate) ||
                (properties[k]! is NSURL),
                "Property values must be of NSString, NSNumber, NSNull, NSDictionary, NSDate, or NSURL. Got: \(String(describing: properties[k as! NSCopying]))")
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
        state.pushToken
    }

    /// Initialize the swift SDK with the given api key.
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
    /// from the current profile. Call ``set(pushToken:)`` again to associate this device to a new profile.
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
        dispatchOnMainThread(action: .setPushToken(apnDeviceToken))
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
            create(event: Event(name: .OpenedPush, properties: properties, profile: [:]))
            Task {
                await MainActor.run {
                    if let url = properties["url"] as? String, let url = URL(string: url) {
                        if let deepLinkHandler = deepLinkHandler {
                            deepLinkHandler(url)
                        } else {
                            UIApplication.shared.open(url)
                        }
                    }
                    completionHandler()
                }
            }

            return true
        }
        return false
    }
}
