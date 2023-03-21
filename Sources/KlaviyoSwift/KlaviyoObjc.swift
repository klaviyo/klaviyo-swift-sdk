//
//  KlaviyoObjc.swift
//
//
//  Created by Noah Durell on 3/21/23.
//

import Foundation

// MARK: Objective-C

@objc
public class KlaviyoObjc: NSObject {
    /// Klaviyo Singleton Instance
    public static let sharedInstance = KlaviyoObjc()

    private static let sdkInstance = KlaviyoSDK()

    // MARK: Klaviyo Payload Keys

    /// Email address key for use in identifying profiles and events.
    public let EmailKey = "$email"

    /// First name key for use in identifying profiles and events.
    public let FirstNameKey = "$first_name"

    /// Last name key for use in identifying profiles and events.
    public let LastNameKey = "$last_name"

    /// Phone number key for use in identifying profiles and events.
    public let PhoneNumberKey = "$phone_number"

    /// Title key for use in identifying profiles and events.
    public let TitleKey = "$title"

    /// Organization for use in identifying profiles and events.
    public let OrganizationKey = "$organization"

    /// City key for use in identifying profiles and events.
    public let CityKey = "$city"

    /// Region key for use in identifying profiles and events.
    public let RegionKey = "$region"

    /// Country key for use in identifying profiles and events.
    public let CountryKey = "$country"

    /// Zip key for use in identifying profiles and events.
    public let ZipKey = "$zip" // postal code where they live

    override private init() {
        super.init()
    }

    /// Initialize the Objective-C SDK with the given api key.
    /// - Parameter apiKey: the public api key assigned to your company.
    @objc
    public class func initialize(with apiKey: String) {
        Self.sdkInstance.initialize(with: apiKey)
    }

    /// Register the current user's email address with Klaivyo.
    /// - Parameter email: the email for the current user.
    @objc
    public func set(email: String) {
        Self.sdkInstance.set(email: email)
    }

    /// Register the current user's phone number with Klaivyo.
    /// - Parameter phoneNumber: the phone number for the current user.
    @objc
    public func set(phoneNumber: String) {
        Self.sdkInstance.set(phoneNumber: phoneNumber)
    }

    /// Register a customer's external id with Klaivyo.
    /// - Parameter externalId: the user's external id (e.g. a user id)
    @objc
    public func set(externalId: String) {
        Self.sdkInstance.set(externalId: externalId)
    }

    /// handle a push
    @objc
    public func handlePush() {}

    @objc
    public func createEvent(eventName: String) {
        createEvent(eventName: eventName,
                    properties: [:],
                    customerProperties: [:])
    }

    @objc
    public func createEvent(eventName: String,
                            properties: [String: AnyHashable]) {
        createEvent(eventName: eventName,
                    properties: properties,
                    customerProperties: [:])
    }

    @objc
    public func createEvent(eventName: String,
                            properties: [String: AnyHashable],
                            customerProperties: [String: AnyHashable]) {
        let event = Event(attributes: .init(name: .CustomEvent(eventName),
                                            properties: properties, profile: customerProperties))
        dispatchOnMainThread(action: .enqueueEvent(event))
    }

    @objc
    public func createProfile(customerProperties: [String: AnyHashable]) {
        if customerProperties.keys.isEmpty {
            return
        }
    }

    @objc
    public func addPushDeviceToken(deviceToken: Data) {
        _ = Self.sdkInstance.set(pushToken: deviceToken)
    }
}
