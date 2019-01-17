//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2019 Klaviyo. All rights reserved.
//


import Foundation
import UIKit

public class Klaviyo : NSObject {
    
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
    let KlaviyoServerURLString = "https://a.klaviyo.com/api"
    let KlaviyoServerTrackEventEndpoint = "/track"
    let KlaviyoServerTrackPersonEndpoint = "/identify"
    
    
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
    var serialQueue : DispatchQueue!
    var eventsQueue : NSMutableArray?
    var peopleQueue : NSMutableArray?
    var urlSession : URLSession?
    var reachability : Reachability?
    var remoteNotificationsEnabled : Bool?
    let urlSessionMaxConnection = 5
    var showNetworkActivityIndicator : Bool = true
    public var requestsList : NSMutableArray = []
    
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
        super.init()
        
        // Dev warnings for incorrect iOS version
        assert(isOperatingMinimumiOSVersion() == true, "operating outdated iOS version. requires >= ios 8")
        // Dev warnings for nil api keys
        assert(apiKey == nil, "api key is nil")
        
        // Create the queue
        serialQueue = DispatchQueue(label: "com.klaviyo.serialQueue")

        // Configure the URL Session
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = urlSessionMaxConnection
        urlSession = URLSession(configuration: config)
        reachability = Reachability(hostname: "www.klaviyo.com")
        
    }
    
    /**
     setupWithPublicAPIKey: sets up the Klaviyo iOS SDK for use in the application. Should be called once upon initial application setup in the AppDelegate didFinishLaunchingWithOptions: Requires an account ID, which can be accessed through Klaviyo.com.
     
     - Parameter apiKey: string representation of the Klaviyo API Key
     */
    public class func setupWithPublicAPIKey(apiKey : String) {
        sharedInstance.apiKey = apiKey
        sharedInstance.unarchive()
        sharedInstance.flush()
        sharedInstance.addNotificationObserver()
    }
    
    /**
     setUpUserEmail: Register the current user's email address with Klaivyo. This can also be done via passing a dictionary containing a user's email to trackEvent.
     
     - Parameter userEmail: the user's email address
     */
    public func setUpUserEmail(userEmail :String) {
        self.userEmail = userEmail
        
        /* Save to nsuser defaults */
        let defaults = UserDefaults.standard
        defaults.setValue(userEmail, forKey: KLEmailNSDefaultsKey)
        
        /* Identify the user in Klaviyo */
        let dictionary = NSMutableDictionary()
        dictionary[KLPersonEmailDictKey] = userEmail
        trackPersonWithInfo(personDictionary: dictionary)
    }
    
    
    /*
     setUpCustomerID: Register the current customer ID and saves it
     If this is called once, there is no need to pass in identifiying dictionaries to tracked events
     */
    public func setUpCustomerID(id: String) {
        let defaults = UserDefaults.standard
        defaults.setValue(id, forKey: KLCustomerIDNSDefaults)
    }
    
    /**
     handlePush: Extracts tracking information from received push notification and sends the data to Klaviyo for push-tracking
     analystics.
     
     - Parameter userInfo: NSDictionary containing the push notification text & metadata
     */
    public func handlePush(userInfo: NSDictionary) {
        if let metadata = userInfo["_k"] as? NSDictionary {
            trackEvent(eventName: KLPersonOpenedPush, properties: metadata)
        } else {
            trackEvent(eventName: KLPersonOpenedPush, properties: userInfo as NSDictionary)
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
        
        var eventName = event
        // Set default track name if none provided
        if (eventName == nil || eventName!.isEmpty) { eventName = "KL_Event" }

        // Check both dictionaries
        let customerPropertiesDict = updatePropertiesDictionary(propDictionary: customerProperties)
        assertPropertyTypes(properties: propertiesDict)
        
        serialQueue.async(execute: {
            let event = NSMutableDictionary()
            
            // Set the apiKey for the event
            if (self.apiKey!.count > 0) {
                event[self.KLEventTrackTokenJSONKey] = self.apiKey
            } else {
                event[self.KLEventTrackTokenJSONKey] = ""
            }
            
            // If it's a push event, set a service key to Klaviyo
            var service: String = "api"
            if eventName == self.KLPersonReceivedPush || eventName == self.KLPersonOpenedPush {
                service = "klaviyo"
            }
            
            // Set the event info
            event[self.KLEventTrackEventJSONKey] = eventName
            event[self.KLEventTrackCustomerPropetiesJSONKey] = customerPropertiesDict
            event[self.KLEventTrackingServiceKey] = service
            
            if let unwrappedPropertiesDict = propertiesDict {
                if unwrappedPropertiesDict.allKeys.count > 0 { event[self.KLEventTrackPropertiesJSONKey] = propertiesDict }
            }
            
            if eventDate != nil { event[self.KLEventTrackTimeJSONKey] = eventDate }
            
            // Add the event to the queue
            self.eventsQueue!.add(event)
            
            if self.eventsQueue!.count > 500 {
                self.eventsQueue!.removeObject(at: 0)
            }
            
            if self.inBackground() {
                self.archiveEvents()
            }
            // execute
            self.flushEvents()
        })
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
        if personDictionary.allKeys.count == 0 {
            return
        }
        // Update properties for JSON encoding
        let personInfoDictionary = updatePropertiesDictionary(propDictionary: personDictionary)
        assertPropertyTypes(properties: personInfoDictionary)
        
        serialQueue.async(execute: {
            let event = NSMutableDictionary()
            
            if self.apiKey!.count > 0 {
                event[self.KLPersonTrackTokenJSONKey] = self.apiKey
            } else {
                event[self.KLPersonTrackTokenJSONKey] = ""
            }
            
            event[self.KLPersonPropertiesJSONKey] = personInfoDictionary
            self.peopleQueue!.add(_: event)
            
            if self.peopleQueue!.count > 500 {
                self.peopleQueue!.removeObject(at: 0)
            }
            
            if self.inBackground() {
                self.archivePeople()
            }
            
            self.flushPeople()
        })
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
        
        let defaults = UserDefaults.standard
        defaults.setValue(apnDeviceToken, forKey: CustomerPropertiesAPNTokensDictKey)
    }
    
    
    
    /**
     updatePropertiesDictionary: Internal function that configures the properties dictionary so that it holds the minimum info needed to track events and users
     - Parameter propertiesDictionary: dictionary of properties passed in for a given event or user. May be nil if no parameters are given.
     - Returns: Void
     */
    internal func updatePropertiesDictionary(propDictionary: NSDictionary?)->NSDictionary {
        var propertiesDictionary = propDictionary
        if propertiesDictionary == nil {
            propertiesDictionary = NSMutableDictionary()
        }
        
        let returnDictionary = propertiesDictionary as! NSMutableDictionary
        
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
        if let idExists = returnDictionary[KLPersonIDDictKey] {
            let defaults = UserDefaults.standard
            defaults.setValue(idExists, forKey: KLCustomerIDNSDefaults)
        } else if let customerID =  UserDefaults.standard.value(forKey: KLCustomerIDNSDefaults) as? String {
            returnDictionary[KLPersonIDDictKey] = customerID
        }
        
        // Set the user's timezone: Note if the customer exists this will override their current profile
        // Alternatively, could create a customer mobile timezone property instead using a different key
        let timezone = NSTimeZone.local.identifier
        returnDictionary[KLTimezone] = timezone
        
        // If push notifications are used, append them
        if apnDeviceToken != nil {
            returnDictionary[CustomerPropertiesAppendDictKey] = [CustomerPropertiesAPNTokensDictKey : apnDeviceToken!]
        }
        
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
     isOperatingMinimumiOSVersion: internal alert function for development purposes. Asserts an error if the application is running an OS system below 8.0.0.
     
     - Returns: A boolean value where true means the os is compatible and the SDK can be used
     */
    private func isOperatingMinimumiOSVersion() -> Bool {
        return ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 8,
                                                                             minorVersion: 0,
                                                                             patchVersion: 0))
    }
    
    /**
     removeNotificationObserver() removes the observers that are set up upon instantiation.
     */
    func removeNotificatoinObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationDidBecomeActiveNotification")
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationDidEnterBackgroundNotification")
        notificationCenter.removeObserver(self, forKeyPath: "UIApplicationWillTerminateNotification")
        notificationCenter.removeObserver(self, forKeyPath: "ReachabilityChangedNotification")
    }
    
    func removeNotificationsObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self)
    }
    
    @objc func applicationDidBecomeActiveNotification(notification: NSNotification) {
        // clear all notification badges anytime the user opens the app
        UIApplication.shared.applicationIconBadgeNumber = 0
        try? reachability?.startNotifier()
        
        // identify the user
        let dict: NSMutableDictionary = ["$anonymous": iOSIDString]
        trackPersonWithInfo(personDictionary: dict)
    }
    
    @objc func applicationDidEnterBackgroundNotification(notification: NSNotification){
        reachability?.stopNotifier()
    }
    
    @objc func applicationWillTerminate(notification : NSNotification) {
        archive()
    }
    
    //: Persistence Functionality
    
    /**
    filePathForData: returns a string representing the filepath where archived event queues are stored
    
    - Parameter data: name representing the event queue to locate (will be either people or events)
    - Returns: filePath string representing the file location
    */
    private func filePathForData(data: String)->String {
        let fileName = "/klaviyo-\(apiKey!)-\(data).plist"
        let directory = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).last
        let filePath = directory!.appending(fileName)
        return filePath
    }
    
    // Helper functions
    private func eventsFilePath()->String {
        return filePathForData(data: "events")
    }
    
    private func peopleFilePath()->String{
        return filePathForData(data: "people")
    }
    
    /*
    archiveEvents: copies the event queue and archives it to the appropriate directory location
    */
    private func archiveEvents() {
        let filePath = eventsFilePath()
        let eventsQueueCopy = eventsQueue!
        if !NSKeyedArchiver.archiveRootObject(eventsQueueCopy, toFile: filePath) {
            print("unable to archive the events data")
        }
    }
    /*
    archivePeople: copies the people queue and archives it to the appropriate directory location
    */
    private func archivePeople() {
        let filePath = peopleFilePath()
        let peopleQueueCopy : NSMutableArray = peopleQueue!
        if !NSKeyedArchiver.archiveRootObject(peopleQueueCopy, toFile: filePath) {
            print("unable to archive the people data")
        }
    }
    
    private func archive() {
        archiveEvents()
        archivePeople()
    }
    
    private func unarchive() {
        unarchiveEvents()
        unarchivePeople()
    }
    
    private func unarchiveEvents() {
        eventsQueue = unarchiveFromFile(filePath: eventsFilePath()) as? NSMutableArray
        if eventsQueue == nil { eventsQueue = NSMutableArray() }
    }
    
    private func unarchivePeople() {
        peopleQueue = unarchiveFromFile(filePath: peopleFilePath()) as? NSMutableArray
        if peopleQueue == nil { peopleQueue = NSMutableArray() }
    }
    
    /**
     unarchiveFromFile: takes a file path of store data and attempts to
     */
    private func unarchiveFromFile(filePath: String)-> AnyObject? {
        var unarchivedData : AnyObject? = nil
        
        unarchivedData =  NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as AnyObject
        
        if FileManager.default.fileExists(atPath: filePath) {
            var removed: Bool
            
            do {
                try FileManager.default.removeItem(atPath: filePath)
                removed = true
            }
            catch {
                removed = false
            }
            if !removed {print("Unable to remove archived data!")}
            return unarchivedData
        }
        return unarchivedData
    }
    
    // MARK: Application Helpers
    private func inBackground() -> Bool {
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState == UIApplication.State.background
        }
    }
    
    private func updateNetworkActivityIndicator(on: Bool) {
        if showNetworkActivityIndicator {
            DispatchQueue.main.async {
                UIApplication.shared.isNetworkActivityIndicatorVisible = on
            }
        }
    }
    
    
    //: MARK: Network Control
    
    /*
    Internal function that initiates the flushing of data
    */
    private func flush() {
        
        flushEvents()
        flushPeople()
    }
    
    private func flushEvents() {
        serialQueue.async(execute: {
            self.flushQueue(queue: self.eventsQueue!, endpoint: self.KlaviyoServerTrackEventEndpoint)
        })
    }
    
    private func flushPeople() {
        serialQueue.async(execute: {
            self.flushQueue(queue: self.peopleQueue!, endpoint: self.KlaviyoServerTrackPersonEndpoint)
        })
    }
    
    /**
     flushQueue: Iterates through an array of events and produces the relevant API request
     - Parameter queue: an array of events
     - Parameter endpoint: the api endpoint
     */
    private func flushQueue(queue: NSMutableArray, endpoint: String) {
        
        if !isHostReachable() {
            return
        }
        
        let currentQueue : NSArray = queue
        
        
        for item in currentQueue {
            let i = item as! NSDictionary
            
            //Encode the parameters
            let requestParamData = encodeAPIParamData(dict: i)
            let param = "data=\(requestParamData)"
            
            //Construct the API Request
            let request = apiRequestWithEndpoint(endpoint: endpoint, param: param)

            //Format and append the request for accessible logging
            let requestString = "Endpoint: \(endpoint) \t Payload: \(i)"
            requestsList.add(requestString)

            updateNetworkActivityIndicator(on: true)
            
            //Execute
            let task : URLSessionDataTask = urlSession!.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
                self.serialQueue.async(execute: {
                    if(error == nil) {
                        let response = NSString(data: data!, encoding: String.Encoding.utf8.rawValue as UInt)
                        if response!.intValue == 0 {
                            print("api rejected item: \(endpoint), \(i)")
                        }
                        queue.remove(_: i)
                    }
                    if queue.count == 0 {
                        self.updateNetworkActivityIndicator(on: false)
                    }
                })
            })
            task.resume()
        }
    }
    
    
    /**
     apiRequestWithEndpoint: Internal function that returns an NSURLRequest for the Klaviyo Server
     - Parameter endpoint: String representing the type of event (track or identify)
     - Parameter param: String representing the properties of the event or the identify call
     - Returns: an NSURLRequest for the API call
     */
    private func apiRequestWithEndpoint(endpoint : String, param: String)-> NSURLRequest {
        let urlString = KlaviyoServerURLString+endpoint+"?"+param
        let url = NSURL(string: urlString)
        
        let request = NSMutableURLRequest(url: url! as URL)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.httpMethod = "GET"
        
        return request
    }
    
    // Reachability Functions
    
    private func isHostReachable()->Bool {
        return reachability?.currentReachabilityStatus != Reachability.NetworkStatus.notReachable
    }
    
    @objc internal func hostReachabilityChanged(note : NSNotification) {
        if isHostReachable() {
            flush()
        }
    }
    
    // :MARK- Encoding & Decoding functions
    
    /**
    encodeAPIParamData: Internal function that encodes API dictionary data to base64 and returns a string
    - Parameter dict: an NSDictionary representing the data to be encoded for a given event
    - Returns: an encoded string
    */
    private func encodeAPIParamData(dict: NSDictionary)->String {
        var b64String = ""
        let data : NSData? = JSONSerializeObject(obj: dict)
        
        if data != nil {
            let characterSet = NSMutableCharacterSet.urlQueryAllowed
            b64String = data!.base64EncodedString()
            b64String = b64String.addingPercentEncoding(withAllowedCharacters: characterSet)!
        }
        
        return b64String
    }
    
    /**
     JSONSerializeObject: serializes an AnyObject into an NSData Object.
     
     - Parameter obj: the object to be serialized
     - Returns: NSData representation of the object
     */
    private func JSONSerializeObject(obj : AnyObject)-> NSData? {
        
        let coercedobj = JSONSerializableObjectForObject(obj: obj)
        var error : NSError? = nil
        var data : NSData? = nil
        
        if JSONSerialization.isValidJSONObject(obj) {
            do {
                data = try JSONSerialization.data(withJSONObject: coercedobj, options: .prettyPrinted) as NSData
            }
            catch let errors as NSError{
                data = nil
                error = errors
                print("exception encoding the api data: \(errors)")
            }
            catch {
                print("unknown error")
            }
            if error == nil { return data }
            print("Error parsing the json: \(String(describing: error))")
        }
        
        return data
    }
    
    /**
     JSONSerializableObjectForObject: Function checks & converts data into approved data types for JSON
     
     :param: obj type AnyObject
     :returns: an AnyObject that has been verified and cleaned
     */
    private func JSONSerializableObjectForObject(obj: AnyObject)-> AnyObject {
        
        if JSONSerialization.isValidJSONObject(obj) {
            return obj
        }
        
        // Apple Documentation: "All objects need to be instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull"
        if (obj is NSString || obj is NSNumber || obj is NSNull) {
            return obj
        }
        
        // recurse through collections and serialize each object
        if (obj is NSArray) {
            let a = NSMutableArray()
            let objects = obj as! NSArray
            for item in objects {
                a.add(_: JSONSerializableObjectForObject(obj: item as AnyObject))
            }
            return a as NSArray
        }
        
        if (obj is NSDictionary) {
            let dict = NSMutableDictionary()
            let objects = obj as! NSDictionary
            
            for key in objects.keyEnumerator() {
                guard let stringKey = key as? String else {
                    print("warning: property keys should be strings. got: \(String(describing: key))")
                    continue
                }
                let v : AnyObject = JSONSerializableObjectForObject(obj: objects[stringKey]! as AnyObject)
                dict[stringKey] = v
            }
            return dict
        }
        
        if (obj is NSDate) {
            return obj.timeIntervalSince1970 as AnyObject

        }
        
        let s = obj.description
        print("Warning, the property values should be valid json types")
        return s as AnyObject
    }
    
}
