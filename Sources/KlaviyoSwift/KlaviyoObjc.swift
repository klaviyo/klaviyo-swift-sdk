//
//  KlaviyoObjc.swift
//
//
//  Created by Noah Durell on 3/21/23.
//

import Foundation
import UserNotifications

// MARK: Objective-C

/// The main interface for the Klaviyo SDK.
/// Create a new instance as follows:
///
/// ```objectivec
/// let sdk = [[KlaviyoObjc alloc] init];
///  [sdk initialize:@"abc123"];
/// ```
///
/// From there you can you can call the additional methods below to track events and profile.
@objc
public class KlaviyoObjc: NSObject {
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

    //  External Id for use in identifying profiles and events.
    public let ExternalIdKey = "$id"

    /// Title key for use in identifying profiles and events.
    public let TitleKey = "$title"

    /// Organization key for use in identifying profiles and events.
    public let OrganizationKey = "$organization"

    // Address 1 key for use in identifying profiles and events.
    public let Address1Key = "$address1"

    // Address 2 key for use in identify profiles and events.
    public let Address2Key = "$address2"

    /// City key for use in identifying profiles and events.
    public let CityKey = "$city"

    /// Region key for use in identifying profiles and events.
    public let RegionKey = "$region"

    /// Country key for use in identifying profiles and events.
    public let CountryKey = "$country"

    /// Zip code key for use in identifying profiles and events.
    public let ZipKey = "$zip"

    /// Latitude key for use in identifying profiles and events.
    public let LatitudeKey = "$latitude"

    /// Longitude key for use in identifying profiles and events.
    public let LongitudeKey = "$longitude"

    /// Time zone key for use in identifying profiles and events.
    public let TimeZoneKey = "$timezone"

    /// Image key for use in identifying profiles and events.
    public let ImageKey = "$image"

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

    /// Track a notificationResponse open event in Klaviyo
    /// - Parameters:
    ///   - notificationResponse: the notification response.
    ///   - completionHandler: the completion handler for this response.
    ///   - Returns: true if the notificaiton originated from Klaviyo, false otherwise.
    @objc
    public func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        Self.sdkInstance.handle(notificationResponse: notificationResponse, withCompletionHandler: completionHandler)
    }

    /// Create and send an event for the current user.
    /// - Parameter eventName: the event to be tracked in Klaviyo
    @objc
    public func createEvent(eventName: String) {
        createEvent(eventName: eventName,
                    properties: [:],
                    customerProperties: [:])
    }

    /// Create and send an event for the current user.
    /// - Parameters:
    ///   - eventName: the name of the event
    ///   - properties: the properties of the event
    @objc
    public func createEvent(eventName: String,
                            properties: [String: AnyHashable]) {
        createEvent(eventName: eventName,
                    properties: properties,
                    customerProperties: [:])
    }

    /// Create and send an event for the current user.
    /// - Parameters:
    ///   - eventName: the name of the event
    ///   - properties: the properties of the event
    ///   - customerProperties: the customer properties associated with the event.
    @objc
    public func createEvent(eventName: String,
                            properties: [String: AnyHashable],
                            customerProperties: [String: AnyHashable]) {
        let event = Event(attributes: .init(name: .CustomEvent(eventName),
                                            properties: properties,
                                            profile: customerProperties))
        dispatchOnMainThread(action: .enqueueEvent(event))
    }

    @objc
    public func createProfile(customerProperties: [String: AnyHashable]) {
        if customerProperties.keys.isEmpty {
            return
        }
        var customerProperties = customerProperties
        let email = customerProperties.removeValue(forKey: EmailKey) as? String
        let phoneNumber = customerProperties.removeValue(forKey: PhoneNumberKey) as? String
        let externalId = customerProperties.removeValue(forKey: ExternalIdKey) as? String
        let firstName = customerProperties.removeValue(forKey: FirstNameKey) as? String
        let lastName = customerProperties.removeValue(forKey: LastNameKey) as? String
        let organization = customerProperties.removeValue(forKey: OrganizationKey) as? String
        let title = customerProperties.removeValue(forKey: TitleKey) as? String
        let image = customerProperties.removeValue(forKey: ImageKey) as? String
        let address1 = customerProperties.removeValue(forKey: Address1Key) as? String
        let address2 = customerProperties.removeValue(forKey: Address1Key) as? String
        let city = customerProperties.removeValue(forKey: CityKey) as? String
        let country = customerProperties.removeValue(forKey: CountryKey) as? String
        let latitude = customerProperties.removeValue(forKey: LatitudeKey) as? Double
        let longitude = customerProperties.removeValue(forKey: LongitudeKey) as? Double
        let region = customerProperties.removeValue(forKey: RegionKey) as? String
        let zip = customerProperties.removeValue(forKey: ZipKey) as? String
        let timezone = customerProperties.removeValue(forKey: TimeZoneKey) as? String

        let profile = Profile(attributes: .init(
            email: email,
            phoneNumber: phoneNumber,
            externalId: externalId,
            firstName: firstName,
            lastName: lastName,
            organization: organization,
            title: title,
            image: image,
            location: .init(
                address1: address1,
                address2: address2,
                city: city,
                country: country,
                latitude: latitude,
                longitude: longitude,
                region: region,
                zip: zip,
                timezone: timezone),
            properties: customerProperties))
        dispatchOnMainThread(action: .enqueueProfile(profile))
    }

    @objc
    public func addPushDeviceToken(deviceToken: Data) {
        _ = Self.sdkInstance.set(pushToken: deviceToken)
    }
}
