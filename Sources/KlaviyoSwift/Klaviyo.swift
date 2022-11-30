//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2022 Klaviyo. All rights reserved.
//


import Foundation
import UIKit

let version = "2.0.0"

public class Klaviyo: NSObject  {
    /*
    Klaviyo Class Constants
    */
    
    // Create the singleton instance
    public static let sharedInstance = Klaviyo()
    
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
    public var KlaviyoServerURLString = "https://a.klaviyo.com/api"
    #else
    let KlaviyoServerURLString = "https://a.klaviyo.com/api"
    #endif
    
    /*
    Current API WorkAround: Update this once the $anonymous in place
    */
    let CustomerPropertiesIDDictKey = "$anonymous"
    
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
    Shared Instance Variables
    */
    var apiKey : String?
    var apnDeviceToken : String?
    var userEmail : String = ""
    let reachability : Reachability
    
    /*
    Computed property for iOSIDString
    :returns: A unique string that represents the device using the application
    */
    var iOSIDString : String {
        return "iOS:" + UIDevice.current.identifierForVendor!.uuidString
    }
    
    /*
    Singleton Initializer. Must be kept private as only one instance can be created.
    */
    private override init() {
        reachability = Reachability(hostname: "a.klaviyo.com")!
        
        super.init()
        
    }
    
    /**
     setupWithPublicAPIKey: sets up the Klaviyo iOS SDK for use in the application. Should be called once upon initial application setup in the AppDelegate didFinishLaunchingWithOptions: Requires an account ID, which can be accessed through Klaviyo.com.
     
     - Parameter apiKey: string representation of the Klaviyo API Key
     */
    public class func setupWithPublicAPIKey(apiKey : String) {
        sharedInstance.apiKey = apiKey
        // TODO: move some of this to engine initialization.
        sharedInstance.unarchive()
        //sharedInstance.flush()
        sharedInstance.addNotificationObserver()
        environment.analytics.engine.initialize(apiKey)
    }
    
    /**
     setUpUserEmail: Register the current user's email address with Klaivyo. This can also be done via passing a dictionary containing a user's email to trackEvent.
     
     - Parameter userEmail: the user's email address
     */
    public func setUpUserEmail(userEmail :String) {
        
        //TODO: migrate this data to KlaviyoState on initialization
//        self.userEmail = userEmail
//
//        /* Save to nsuser defaults */
//        let defaults = UserDefaults.standard
//        defaults.setValue(userEmail, forKey: KLEmailNSDefaultsKey)
//
//        /* Identify the user in Klaviyo */
//        let dictionary = NSMutableDictionary()
//        dictionary[KLPersonEmailDictKey] = userEmail
        environment.analytics.engine.setEmail(userEmail)
    }
    
    
    /*
     setUpCustomerID: Register the current customer ID and saves it
     If this is called once, there is no need to pass in identifiying dictionaries to tracked events
     */
    public func setUpCustomerID(id: String) {
        let defaults = UserDefaults.standard
        defaults.setValue(id, forKey: KLCustomerIDNSDefaults)
        // TODO: figure out what to do with this....
    }
    
    /**
     handlePush: Extracts tracking information from received push notification and sends the data to Klaviyo for push-tracking
     analystics.
     
     - Parameter userInfo: NSDictionary containing the push notification text & metadata
     */
    public func handlePush(userInfo: NSDictionary) {
        if let _ = userInfo["_k"] as? NSDictionary {
            trackEvent(eventName: KLPersonOpenedPush, properties: userInfo)
        }
    }
    
    /**
     trackEvent: KL Event tracking for event name only
     
     - Parameter eventName: name of the event
     */
    public func trackEvent(eventName : String?) {
        trackEvent(eventName: eventName, properties: nil)
    }
    
    /**
     trackEvent: KL Event tracking for event name and customer properties
     
     - Parameter eventName: name of the event
     - Parameter properties: customerProperties
     */
    public func trackEvent(eventName : String?, properties : NSDictionary?) {
        trackEvent(eventName: eventName, customerProperties: nil, properties: properties)
    }
    
    /**
     trackEvent: KL Event tracking for event name, customer & event properties
     
     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter properties: dictionary for event info
     */
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
    public func trackEvent(event: String?, customerProperties: NSDictionary?, propertiesDict: NSDictionary?, eventDate: NSDate?) {
        
        guard let eventName = event, !eventName.isEmpty else {
            environment.logger.error("EventName was nil. Ignoring.")
            return
        }

        // Check both dictionaries
        let customerPropertiesDict = updatePropertiesDictionary(propDictionary: customerProperties)
        assertPropertyTypes(properties: propertiesDict)

        
        // TODO: Might be redundant
        guard apiKey != nil else {
            environment.logger.error("Track event called before API key was set.")
            //TODO: store pending event for when api key is set.
            return
        }
        
        environment.analytics.engine.enqueueLegacyEvent(eventName, propertiesDict ?? NSDictionary(), customerPropertiesDict)
    }
    
    /**
     emailAddressExists: internal helper function that checks if email has been passed in via the setUpUserEmail method
     
     - Returns: true if the email exists, false otherwise
     */
    func emailAddressExists() -> Bool {
        return self.userEmail.count > 0
    }
    
    
    /**
     trackPersonWithInfo: method that creates a Klaviyo person tracking instance that is separate from an event
     
     - Parameter personInfoDictionary: dictionary of user attributes that you wish to track. These can be special properties provided by Klaviyo, such as KLPersonFirstNameDictKey, or created by the user on the fly.
     
     - Returns: Void
     */
    public func trackPersonWithInfo(personDictionary: NSDictionary) {
        // No info, return
        guard !personDictionary.allKeys.isEmpty else {
            return
        }
        
        guard apiKey != nil else {
            environment.logger.error("Track person called before API key was set.")
            //TODO: store pending data for when api key is set.
            return
        }
        
        // Update properties for JSON encoding
        let personInfoDictionary = updatePropertiesDictionary(propDictionary: personDictionary)
        assertPropertyTypes(properties: personInfoDictionary)
        
        environment.analytics.engine.enqueueLegacyProfile(personDictionary)
    }
    
    /**
     addPushDeviceToken: Registers Klaviyo with Apple Push Notifications (APN)
     Private function creates a unique identifier for the device and uses it to track the event
     
     - Parameter deviceToken: token provided by Apple that registers push notifications to the given device
     - Returns: Void
     */
    public func addPushDeviceToken(deviceToken: Data) {
        let apnDeviceToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
        personInfoDictionary[CustomerPropertiesAppendDictKey] = [CustomerPropertiesAPNTokensDictKey: apnDeviceToken]
        trackPersonWithInfo(personDictionary: personInfoDictionary)
//        TODO: Migrate token storage away from here.
        let defaults = UserDefaults.standard
        defaults.setValue(apnDeviceToken, forKey: CustomerPropertiesAPNTokensDictKey)
        environment.analytics.engine.setToken(deviceToken)
    }
    
    /**
     updatePropertiesDictionary: Internal function that configures the properties dictionary so that it holds the minimum info needed to track events and users
     - Parameter propertiesDictionary: dictionary of properties passed in for a given event or user. May be nil if no parameters are given.
     - Returns: Void
     */
    internal func updatePropertiesDictionary(propDictionary: NSDictionary?)->NSDictionary {
        var propertiesDictionary = propDictionary
        if propertiesDictionary == nil {
            propertiesDictionary = NSDictionary()
        }
        
        guard let returnDictionary = propertiesDictionary as? NSMutableDictionary else {
            return NSDictionary()
        }
        
        if emailAddressExists() && returnDictionary[KLPersonEmailDictKey] == nil {
            // if setUpUserEmail has been called & a new value has not been provided; use the passed value
            returnDictionary[KLPersonEmailDictKey] = self.userEmail
        } else if let newEmail = returnDictionary[KLPersonEmailDictKey] {
            // if user provides an email address that takes precendence; save it to defaults & use
            let defaults = UserDefaults.standard
            defaults.setValue(newEmail, forKey: KLEmailNSDefaultsKey)
        } else if let savedEmail = UserDefaults.standard.value(forKey: KLEmailNSDefaultsKey) as? String {
            // check NSuserDefaults for a stored value
            returnDictionary[KLPersonEmailDictKey] = savedEmail
        }
        
        // Set the $anonymous property in case there i sno email address
        returnDictionary[CustomerPropertiesIDDictKey] = self.iOSIDString
        
        // Set the $id if it exists
        if let customerID =  UserDefaults.standard.value(forKey: KLCustomerIDNSDefaults) as? String {
            returnDictionary[KLPersonIDDictKey] = customerID
        }
        
        returnDictionary[KLTimezone] = environment.analytics.timeZone
        
        return returnDictionary
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
    
    /**
     addNotificationObserver: sets up notification observers for various application state changes
     */
    func addNotificationObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.applicationDidBecomeActiveNotification(notification:)), name: NSNotification.Name("UIApplicationDidBecomeActiveNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.applicationDidEnterBackgroundNotification(notification:)), name: NSNotification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.applicationWillTerminate(notification:)), name: NSNotification.Name("UIApplicationWillTerminateNotification"), object: nil)
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.hostReachabilityChanged(note:)), name: NSNotification.Name("ReachabilityChangedNotification") , object: nil)
    }
    
    /**
     removeNotificationObserver() removes the observers that are set up upon instantiation.
     */
    func removeNotificatoinObserver() {
        // TODO: migrate to engine
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationDidBecomeActiveNotification")
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationDidEnterBackgroundNotification")
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationWillTerminateNotification")
        notificationCenter.removeObserver(self, forKeyPath: "ReachabilityChangedNotification")
    }
    
    func removeNotificationsObserver() {
        // TODO: Migrate handling of this to engine, archive state at this point.
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self)
    }
    
    @objc func applicationDidBecomeActiveNotification(notification: NSNotification) {
        // TODO: Migrate handling of this to engine, archive state at this point.
        try? reachability.startNotifier()
        
        // identify the user
        let dict: NSMutableDictionary = ["$anonymous": iOSIDString]
        trackPersonWithInfo(personDictionary: dict)
        environment.analytics.engine.start()
    }
    
    @objc func applicationDidEnterBackgroundNotification(notification: NSNotification){
        // TODO: Migrate handling of this to engine, archive state at this point.
        // TODO: Mak sure this actually makes to do...make turn it back on somewhere?
        reachability.stopNotifier()
        environment.analytics.engine.stop()
    }
    
    @objc func applicationWillTerminate(notification : NSNotification) {
        // TODO: Migrate handling of this to engine, archive state at this point.
        environment.analytics.engine.stop()
    }
    
    //: Persistence Functionality
    
    // Helper functions
    private func eventsFilePath() -> URL? {
        guard let apiKey = apiKey else {
            return nil
        }
        return filePathForData(apiKey: apiKey, data: "events")
    }
    
    private func peopleFilePath() -> URL? {
        guard let apiKey = apiKey else {
            return nil
        }
        return filePathForData(apiKey: apiKey, data: "people")
    }
    
    private func unarchive() {
        unarchiveEvents()
        unarchivePeople()
    }
    
    private func unarchiveEvents() {
        guard let fileURL = eventsFilePath() else {
            eventsQueue = NSMutableArray()
            return
        }
        eventsQueue = unarchiveFromFile(fileURL: fileURL)
        if eventsQueue == nil { eventsQueue = NSMutableArray() }
    }
    
    private func unarchivePeople() {
        guard let fileURL = peopleFilePath() else {
            peopleQueue = NSMutableArray()
            return
        }
        peopleQueue = unarchiveFromFile(fileURL: fileURL)
        if peopleQueue == nil { peopleQueue = NSMutableArray() }
    }
    
    // MARK: Application Helpers
    private func inBackground() -> Bool {
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState == UIApplication.State.background
        }
    }
    
    
    // Reachability Functions
    
    private func isHostReachable()->Bool {
        return reachability.currentReachabilityStatus != Reachability.NetworkStatus.notReachable
    }
    
    @objc internal func hostReachabilityChanged(note : NSNotification) {
        if isHostReachable() {
            environment.analytics.engine.flush()
        }
    }

}
