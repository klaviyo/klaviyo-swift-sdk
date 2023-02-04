//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//


import Foundation
import UIKit


private func dispatchOnMainThread(action: KlaviyoAction) {
    Task {
        await MainActor.run {
            _ = environment.analytics.store.send(action)
        }
    }
}

// MARK: Objective-C

@objc
public class Klaviyo: NSObject  {
   
    /*
    Klaviyo Class Constants
    */
    
    // Create the singleton instance
    public static let sharedInstance = Klaviyo()
    
    private static let sdkInstance = KlaviyoSDK()
    
    /*
    Klaviyo JSON Key Constants
    */
    
    // KL Definitions File: JSON Keys for Tracking Events
    let KLEventTrackTokenJSONKey = "token"
    let KLEventTrackEventJSONKey = "event"
    let KLEventTrackCustomerPropetiesJSONKey = "customer_properties" //must use id or email
    let KLEventTrackingServiceKey = "service"
    
    //Optional Event Tracking Properties
    let KLEventTrackPropertiesJSONKey = "properties"
    let KLEventTrackTimeJSONKey = "time"
    public let KLEventTrackPurchasePlatform = "platform"
    
    // KL Definitions File: JSON Keys for Tracking People
    let KLPersonTrackTokenJSONKey = "token"
    let KLPersonPropertiesJSONKey = "properties" // same as customer properties
    
    // Push Notification Event Tracking
    public let KLPersonReceivedPush = "Received Push"
    public let KLPersonOpenedPush = "$opened_push"
    public let KLMessageDimension = "$message"
    
    // KL Definitions File: API URL Constants

    let KlaviyoServerTrackEventEndpoint = "/track"
    let KlaviyoServerTrackPersonEndpoint = "/identify"
    
    #if DEBUG
    public var KlaviyoServerURLString = "https://a.klaviyo.com/"
    #else
    let KlaviyoServerURLString = "https://a.klaviyo.com/"
    #endif
    
    let CustomerPropertiesAppendDictKey = "$append"
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
    public let KLPersonEmailDictKey = "$email" // email address
    private let KLEmailNSDefaultsKey = "$kl_email"
    public let KLPersonFirstNameDictKey = "$first_name" // first name
    public let KLPersonLastNameDictKey = "$last_name" // last name
    public let KLPersonPhoneNumberDictKey = "$phone_number" // phone number
    public let KLPersonTitleDictKey = "$title" // title at their business or organization
    public let KLPersonOrganizationDictKey = "$organization" // business or organization they belong to
    public let KLPersonCityDictKey = "$city" // city they live in
    public let KLPersonRegionDictKey = "$region" // region or state they live in
    public let KLPersonCountryDictKey = "$country" // country they live in
    public let KLPersonZipDictKey = "$zip" // postal code where they live
    
    /*
    Singleton Initializer. Must be kept private as only one instance can be created.
    */
    private override init() {
        super.init()
    }
    
    /**
     setupWithPublicAPIKey: sets up the Klaviyo iOS SDK for use in the application. Should be called once upon initial application setup in the AppDelegate didFinishLaunchingWithOptions: Requires an account ID, which can be accessed through Klaviyo.com.
     
     - Parameter apiKey: string representation of the Klaviyo API Key
     */
    @objc
    public class func setupWithPublicAPIKey(apiKey: String) {
        //_ avoids warning from xcode
        Klaviyo.sdkInstance.initialize(with: apiKey)
    }
    
    /**
     setUpUserEmail: Register the current user's email address with Klaivyo. This can also be done via passing a dictionary containing a user's email to trackEvent.
     
     - Parameter userEmail: the user's email address
     */
    @objc
    public func setUpUserEmail(userEmail :String) {
        Klaviyo.sdkInstance.set(email: userEmail)
    }
    
    
    /*
     setUpCustomerID: Register the current customer ID and saves it
     If this is called once, there is no need to pass in identifiying dictionaries to tracked events
     */
    @objc
    public func setUpCustomerID(id: String) {
        Klaviyo.sdkInstance.set(externalId: id)
    }
    
    /**
     handlePush: Extracts tracking information from received push notification and sends the data to Klaviyo for push-tracking
     analystics.
     
     - Parameter userInfo: NSDictionary containing the push notification text & metadata
     */
    @objc
    public func handlePush(userInfo: NSDictionary) {
        Klaviyo.sdkInstance.handle(remoteNotification: userInfo as! [AnyHashable : Any]) { result in
            // Empty implementation
        }
    }
    
    /**
     trackEvent: KL Event tracking for event name only
     
     - Parameter eventName: name of the event
     */
    @objc
    public func trackEvent(eventName : String?) {
        trackEvent(eventName: eventName, properties: nil)
    }
    
    /**
     trackEvent: KL Event tracking for event name and customer properties
     
     - Parameter eventName: name of the event
     - Parameter properties: customerProperties
     */
    @objc
    public func trackEvent(eventName : String?, properties : NSDictionary?) {
        trackEvent(eventName: eventName, customerProperties: nil, properties: properties)
    }
    
    /**
     trackEvent: KL Event tracking for event name, customer & event properties
     
     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter properties: dictionary for event info
     */
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
    @objc
    public func trackEvent(event: String?, customerProperties: NSDictionary?, propertiesDict: NSDictionary?, eventDate: NSDate?) {
        
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
    @objc
    public func trackPersonWithInfo(personDictionary: NSDictionary) {
        // No info, return
        if personDictionary.allKeys.count == 0 {
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
    @objc
    public func addPushDeviceToken(deviceToken: Data) {
        Klaviyo.sdkInstance.set(pushToken: deviceToken)
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
        guard let `properties` = properties else {
            return
        }
        
        for (k, _) in properties {
            assert((properties[k]! is NSString) ||
                (properties[k]! is NSNumber) ||
                (properties[k]! is NSNull) ||
                (properties[k]! is NSArray) ||
                (properties[k]! is NSDictionary) ||
                (properties[k]! is NSDate) ||
                (properties[k]! is NSURL)
                , "Property values must be of NSString, NSNumber, NSNull, NSDictionary, NSDate, or NSURL. Got: \(String(describing: properties[k as! NSCopying]))")
        }
    }
}


struct KlaviyoSDK {
    func initialize(with apiKey: String) {
        dispatchOnMainThread(action: .initialize(apiKey))
    }
    
    func set(profile: Profile) {
        dispatchOnMainThread(action: .enqueueProile(profile))
    }
    
    func resetProfile() {
        dispatchOnMainThread(action: .resetProfile)
    }
    
    func set(email: String) {
        dispatchOnMainThread(action: .setEmail(email))
    }
    
    func set(phoneNumber: String) {
        dispatchOnMainThread(action: .setPhoneNumber(phoneNumber))
    }
    
    func set(externalId: String) {
        dispatchOnMainThread(action: .setExternalId(externalId))
    }
    
    func set(profileAttribute: String, value: Any) {
        // This seems tricky to implement with Any - might need to restrict to something equatable, encodable....
    }
    
    func create(event: Event) {
        dispatchOnMainThread(action: .enqueueEvent(event))
    }
    
    func set(pushToken: Data) {
        let apnDeviceToken = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
        dispatchOnMainThread(action: .setPushToken(apnDeviceToken))
    }
    
    func handle(remoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let properties = userInfo as? [String: Any], let body = properties["body"] as? [String: Any], let _ = body["_k"] {
            create(event: Event(attributes: .init(metric: .init(name: .OpenedPush), properties: properties, profile: [:])))
            completionHandler(.noData)
        }
    }
    
    func handle(notificationResponse: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let properties = notificationResponse.notification.request.content.userInfo as? [String: Any],
           let body = properties["body"] as? [String: Any], let _ = body["_k"] {
            create(event: Event(attributes: .init(metric: .init(name: .OpenedPush), properties: properties, profile: [:])))
            completionHandler()
        }
    }
}
