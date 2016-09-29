//
//  Klaviyo.swift
//
//  Created by Katherine Keuper on 9/14/15.
//  Copyright (c) 2015 Klaviyo. All rights reserved.
//


import Foundation
import UIKit
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


open class Klaviyo : NSObject {
    
    /*
    Klaviyo Class Constants
    */
    
    // Create the singleton instance
    open static let sharedInstance = Klaviyo()
    
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
    open let KLEventTrackPurchasePlatform = "platform"
    
    // KL Definitions File: JSON Keys for Tracking People
    let KLPersonTrackTokenJSONKey = "token"
    let KLPersonPropertiesJSONKey = "properties" // same as customer properties
    
    // Push Notification Event Tracking
    open let KLPersonReceivedPush = "Received Push"
    open let KLPersonOpenedPush = "$opened_push"
    open let KLMessageDimension = "$message"
    
    // KL Definitions File: API URL Constants
    let KlaviyoServerURLString = "https://a.klaviyo.com/api"
    let KlaviyoServerTrackEventEndpoint = "/track"
    let KlaviyoServerTrackPersonEndpoint = "/identify"
    
    
    /*
    Current API WorkAround: Update this once the $anonymous in place
    */
    let CustomerPropertiesIDDictKey = "$anonymous"
    
    let CustomerPropertiesAppendDictKey = "$append"
    let CustomerPropertiesAPNTokensDictKey = "$ios_tokens" //tokens for push notification
    let KLRegisterAPNDeviceTokenEvent = "KL_ReceiveNotificationsDeviceToken"
    
    // Track event special info dict keys
    let KLEventIDDictKey = "$event_id" // unique identifier for an event
    let KLEventValueDictKey = "$value" // a numeric value to associate with this special event
    
    // Track person special info dict keys
    let KLPersonIDDictKey = "$id" // your unique identifier for a person
    fileprivate let KLCustomerIDNSDefaults = "$kl_customerID"
    let KLPersonDeviceIDDictKey = "$device_id"
    fileprivate let KLTimezone = "Mobile Timezone"
    
    // Public Info Dictionary Keys
    open let KLPersonEmailDictKey = "$email" // email address
    fileprivate let KLEmailNSDefaultsKey = "$kl_email"
    open let KLPersonFirstNameDictKey = "$first_name" // first name
    open let KLPersonLastNameDictKey = "$last_name" // last name
    open let KLPersonPhoneNumberDictKey = "$phone_number" // phone number
    open let KLPersonTitleDictKey = "$title" // title at their business or organization
    open let KLPersonOrganizationDictKey = "$organization" // business or organization they belong to
    open let KLPersonCityDictKey = "$city" // city they live in
    open let KLPersonRegionDictKey = "$region" // region or state they live in
    open let KLPersonCountryDictKey = "$country" // country they live in
    open let KLPersonZipDictKey = "$zip" // postal code where they live
    
    
    
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
    fileprivate override init() {
        super.init()
        
        // Dev warnings for incorrect iOS version
        assert(isOperatingMinimumiOSVersion() == true, "operating outdated iOS version. requires >= ios 8")
        // Dev warnings for nil api keys
        assert(apiKey == nil, "api key is nil")
        
        // Create the queue
        serialQueue = DispatchQueue(label: "com.klaviyo.serialQueue", attributes: [])
        
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
    open class func setupWithPublicAPIKey(_ apiKey : String) {
        sharedInstance.apiKey = apiKey
        sharedInstance.unarchive()
        sharedInstance.flush()
        sharedInstance.addNotificationObserver()
    }
    
    /**
     setUpUserEmail: Register the current user's email address with Klaivyo. This can also be done via passing a dictionary containing a user's email to trackEvent.
     
     - Parameter userEmail: the user's email address
     */
    open func setUpUserEmail(_ userEmail :String) {
        self.userEmail = userEmail
        
        /* Save to nsuser defaults */
        let defaults = UserDefaults.standard
        defaults.setValue(userEmail, forKey: KLEmailNSDefaultsKey)
        
        /* Identify the user in Klaviyo */
        let dictionary = NSMutableDictionary()
        dictionary[KLPersonEmailDictKey] = userEmail
        trackPersonWithInfo(dictionary)
    }
    
    
    /*
     setUpCustomerID: Register the current customer ID and saves it
     If this is called once, there is no need to pass in identifiying dictionaries to tracked events
     */
    open func setUpCustomerID(_ id: String) {
        let defaults = UserDefaults.standard
        defaults.setValue(id, forKey: KLCustomerIDNSDefaults)
    }
    
    /**
     handlePush: Extracts tracking information from received push notification and sends the data to Klaviyo for push-tracking
     analystics.
     
     - Parameter userInfo: NSDictionary containing the push notification text & metadata
     */
    open func handlePush(_ userInfo: [AnyHashable: Any]) {
        if let metadata = userInfo["_k"] as? [AnyHashable: Any] {
            // Track the push open
            trackEvent(KLPersonOpenedPush, properties: metadata as NSDictionary?)
        } else {
            trackEvent(KLPersonOpenedPush, properties: userInfo as NSDictionary?)
        }
    }
    
    /**
     trackEvent: KL Event tracking for event name only
     
     - Parameter eventName: name of the event
     */
    open func trackEvent(_ eventName : String?) {
        trackEvent(eventName, properties: nil)
    }
    
    /**
     trackEvent: KL Event tracking for event name and customer properties
     
     - Parameter eventName: name of the event
     - Parameter properties: customerProperties
     */
    open func trackEvent(_ eventName : String?, properties : NSDictionary?) {
        trackEvent(eventName, customerProperties: nil, properties: properties)
    }
    
    /**
     trackEvent: KL Event tracking for event name, customer & event properties
     
     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter properties: dictionary for event info
     */
    open func trackEvent(_ eventName: String?, customerProperties: NSDictionary?, properties: NSDictionary?) {
        trackEvent(eventName, customerProperties: customerProperties, propertiesDict: properties, eventDate: nil)
    }
    
    /**
     trackEvent: KL Event tracking using all possible parameters
     
     - Parameter eventName: name of the event
     - Parameter customerPropertiesDict: dictionary for user info
     - Parameter propertiesDict: dictionary for event info
     - Parameter eventDate: date of the event
     */
    open func trackEvent(_ event: String?, customerProperties: NSDictionary?, propertiesDict: NSDictionary?, eventDate: Date?) {
        
        var eventName = event
        // Set default track name if none provided
        if (eventName == nil || eventName!.isEmpty) { eventName = "KL_Event" }
        
        // Check both dictionaries
        let customerPropertiesDict = updatePropertiesDictionary(customerProperties)
        assertPropertyTypes(propertiesDict)
        
        self.serialQueue!.async(execute: {
            let event = NSMutableDictionary()
            
            // Set the apiKey for the event
            if (self.apiKey!.characters.count > 0) {
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
            
            if propertiesDict?.allKeys.count > 0 { event[self.KLEventTrackPropertiesJSONKey] = propertiesDict }
            
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
    func emailAddressExists()->Bool {
        return (self.userEmail.characters.count > 0) ?? false
    }
    
    
    /**
     trackPersonWithInfo: method that creates a Klaviyo person tracking instance that is separate from an event
     
     - Parameter personInfoDictionary: dictionary of user attributes that you wish to track. These can be special properties provided by Klaviyo, such as KLPersonFirstNameDictKey, or created by the user on the fly.
     
     - Returns: Void
     */
    open func trackPersonWithInfo(_ personDictionary: NSDictionary) {
        // No info, return
        if personDictionary.allKeys.count == 0 {
            return
        }
        // Update properties for JSON encoding
        let personInfoDictionary = updatePropertiesDictionary(personDictionary)
        assertPropertyTypes(personInfoDictionary)
        
        self.serialQueue!.async(execute: {
            let event = NSMutableDictionary()
            
            if self.apiKey!.characters.count > 0 {
                event[self.KLPersonTrackTokenJSONKey] = self.apiKey
            } else {
                event[self.KLPersonTrackTokenJSONKey] = ""
            }
            
            event[self.KLPersonPropertiesJSONKey] = personInfoDictionary
            self.peopleQueue!.add(event)
            
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
    open func addPushDeviceToken(_ deviceToken: Data) {
        
        let characterSet = CharacterSet(charactersIn: "<>")
        let trimEnds = deviceToken.description.trimmingCharacters(in: characterSet)
        let cleanToken = trimEnds.replacingOccurrences(of: " ", with: "")
        
        apnDeviceToken = cleanToken

        if apnDeviceToken != nil {
            let personInfoDictionary : NSMutableDictionary = NSMutableDictionary()
            personInfoDictionary[CustomerPropertiesAppendDictKey] = [CustomerPropertiesAPNTokensDictKey: apnDeviceToken!]
            trackPersonWithInfo(personInfoDictionary)
        }
    }
    
    
    
    /**
     updatePropertiesDictionary: Internal function that configures the properties dictionary so that it holds the minimum info needed to track events and users
     - Parameter propertiesDictionary: dictionary of properties passed in for a given event or user. May be nil if no parameters are given.
     - Returns: Void
     */
    fileprivate func updatePropertiesDictionary(_ propDictionary: NSDictionary?)->NSDictionary {
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
        let timezone = TimeZone.autoupdatingCurrent.identifier
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
    fileprivate func assertPropertyTypes(_ properties: NSDictionary?) {
        guard let _ = properties as NSDictionary! else {
            return
        }
        
        for (k, _) in properties! {
            assert((properties![k as! NSCopying]! as AnyObject) is NSString || (properties![k as! NSCopying]! as AnyObject) is NSNumber || (properties![k as! NSCopying]! as AnyObject) is NSNull || (properties![k as! NSCopying]! as AnyObject) is NSArray || (properties![k as! NSCopying]! as AnyObject) is NSDictionary
                || (properties![k as! NSCopying]! as AnyObject) is Date || properties![k as! NSCopying]! is URL
                , "Property values must be of NSString, NSNumber, NSNull, NSDictionary, NSDate, or NSURL. Got: \(properties![k as! NSCopying])")
        }
    }
    
    /**
     addNotificationObserver: sets up notification observers for various application state changes
     */
    func addNotificationObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.applicationDidBecomeActiveNotification(_:)), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.applicationDidEnterBackgroundNotification(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        notificationCenter.addObserver(self, selector: #selector(UIApplicationDelegate.applicationWillTerminate(_:)), name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
        notificationCenter.addObserver(self, selector: #selector(Klaviyo.hostReachabilityChanged(_:)), name: ReachabilityChangedNotification, object: nil)
    }
    
    /**
     isOperatingMinimumiOSVersion: internal alert function for development purposes. Asserts an error if the application is running an OS system below 8.0.0.
     
     - Returns: A boolean value where true means the os is compatible and the SDK can be used
     */
    fileprivate func isOperatingMinimumiOSVersion()->Bool {
        return ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 8, minorVersion: 0, patchVersion: 0)) ?? false
    }
    
    /**
     removeNotificationObserver() removes the observers that are set up upon instantiation.
     */
    func removeNotificatoinObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, forKeyPath: NSNotification.Name.UIApplicationDidBecomeActive.rawValue)
        notificationCenter.removeObserver(self, forKeyPath: NSNotification.Name.UIApplicationDidEnterBackground.rawValue)
        notificationCenter.removeObserver(self, forKeyPath: NSNotification.Name.UIApplicationWillTerminate.rawValue)
        notificationCenter.removeObserver(self, forKeyPath: ReachabilityChangedNotification.rawValue)
    }
    
    func removeNotificationsObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self)
    }
    
    func applicationDidBecomeActiveNotification(_ notification: Notification) {
        // clear all notification badges anytime the user opens the app
        UIApplication.shared.applicationIconBadgeNumber = 0
        do {
            try reachability?.startNotifier()
        } catch {
            // reachability errored
        }
        
        // identify the user
        let dict: NSMutableDictionary = ["$anonymous": iOSIDString]
        trackPersonWithInfo(dict)
    }
    
    func applicationDidEnterBackgroundNotification(_ notification: Notification){
        reachability?.stopNotifier()
    }
    
    func applicationWillTerminate(_ notification : Notification) {
        archive()
    }
    
    //: Persistence Functionality
    
    /**
    filePathForData: returns a string representing the filepath where archived event queues are stored
    
    - Parameter data: name representing the event queue to locate (will be either people or events)
    - Returns: filePath string representing the file location
    */
    fileprivate func filePathForData(_ data: String)->String {
        let fileName = "/klaviyo-\(apiKey!)-\(data).plist"
        let directory = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).last
        let filePath = directory! + fileName
        return filePath
    }
    
    // Helper functions
    fileprivate func eventsFilePath()->String {
        return filePathForData("events")
    }
    
    fileprivate func peopleFilePath()->String{
        return filePathForData("people")
    }
    
    /*
    archiveEvents: copies the event queue and archives it to the appropriate directory location
    */
    fileprivate func archiveEvents() {
        let filePath = eventsFilePath()
        let eventsQueueCopy = eventsQueue!
        if !NSKeyedArchiver.archiveRootObject(eventsQueueCopy, toFile: filePath) {
            print("unable to archive the events data")
        }
    }
    /*
    archivePeople: copies the people queue and archives it to the appropriate directory location
    */
    fileprivate func archivePeople() {
        let filePath = peopleFilePath()
        let peopleQueueCopy : NSMutableArray = peopleQueue!
        if !NSKeyedArchiver.archiveRootObject(peopleQueueCopy, toFile: filePath) {
            print("unable to archive the people data")
        }
    }
    
    fileprivate func archive() {
        archiveEvents()
        archivePeople()
    }
    
    fileprivate func unarchive() {
        unarchiveEvents()
        unarchivePeople()
    }
    
    fileprivate func unarchiveEvents() {
        eventsQueue = unarchiveFromFile(eventsFilePath()) as! NSMutableArray?
        if eventsQueue == nil { eventsQueue = NSMutableArray() }
    }
    
    fileprivate func unarchivePeople() {
        peopleQueue = unarchiveFromFile(peopleFilePath()) as! NSMutableArray?
        if peopleQueue == nil { peopleQueue = NSMutableArray() }
    }
    
    /**
     unarchiveFromFile: takes a file path of store data and attempts to
     */
    fileprivate func unarchiveFromFile(_ filePath: String)-> AnyObject? {
        var unarchivedData : AnyObject? = nil
        
        unarchivedData =  NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as AnyObject?
        
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
    fileprivate func inBackground()->Bool {
        return UIApplication.shared.applicationState == UIApplicationState.background
    }
    
    fileprivate func updateNetworkActivityIndicator(_ on : Bool) {
        if showNetworkActivityIndicator {
            UIApplication.shared.isNetworkActivityIndicatorVisible = on
        }
    }
    
    
    //: MARK: Network Control
    
    /*
    Internal function that initiates the flushing of data
    */
    fileprivate func flush() {
        
        flushEvents()
        flushPeople()
    }
    
    fileprivate func flushEvents() {
        self.serialQueue!.async(execute: {
            self.flushQueue(self.eventsQueue!, endpoint: self.KlaviyoServerTrackEventEndpoint)
        })
    }
    
    fileprivate func flushPeople() {
        self.serialQueue!.async(execute: {
            self.flushQueue(self.peopleQueue!, endpoint: self.KlaviyoServerTrackPersonEndpoint)
        })
    }
    
    /**
     flushQueue: Iterates through an array of events and produces the relevant API request
     - Parameter queue: an array of events
     - Parameter endpoint: the api endpoint
     */
    fileprivate func flushQueue(_ queue: NSMutableArray, endpoint: String) {
        
        if !isHostReachable() {
            return
        }
        
        let currentQueue : NSArray = queue
        
        
        for item in currentQueue {
            let i = item as! NSDictionary
            
            //Encode the parameters
            let requestParamData = encodeAPIParamData(i)
            let param = "data=\(requestParamData)"
            
            //Construct the API Request
            let request = apiRequestWithEndpoint(endpoint, param: param)
            updateNetworkActivityIndicator(true)
            
            //Execute
            let task : URLSessionDataTask = urlSession!.dataTask(with: request, completionHandler: { (data, response, error) -> Void in
                self.serialQueue!.async(execute: {
                    if(error != nil) {
                        print("network failure: \(error)")
                    } else {
                        let response = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                        if response!.intValue == 0 {
                            print("api rejected item: \(endpoint), \(i)")
                        }
                        queue.remove(i)
                    }
                    if queue.count == 0 {
                        self.updateNetworkActivityIndicator(false)
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
    fileprivate func apiRequestWithEndpoint(_ endpoint : String, param: String)-> URLRequest {
        let urlString = KlaviyoServerURLString+endpoint+"?"+param
        let url = URL(string: urlString)
        
        let request = NSMutableURLRequest(url: url!)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.httpMethod = "GET"
        
        return request as URLRequest
    }
    
    // Reachability Functions
    
    fileprivate func isHostReachable()->Bool {
        return reachability?.currentReachabilityStatus != Reachability.NetworkStatus.notReachable
    }
    
    internal func hostReachabilityChanged(_ note : Notification) {
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
    fileprivate func encodeAPIParamData(_ dict: NSDictionary)->String {
        var b64String = ""
        let data : Data? = JSONSerializeObject(dict)
        
        if data != nil {
            let characterSet = NSMutableCharacterSet.urlQueryAllowed
            b64String = data!.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
            b64String = b64String.addingPercentEncoding(withAllowedCharacters: characterSet)!
        }
        
        return b64String
    }
    
    /**
     JSONSerializeObject: serializes an AnyObject into an NSData Object.
     
     - Parameter obj: the object to be serialized
     - Returns: NSData representation of the object
     */
    fileprivate func JSONSerializeObject(_ obj : AnyObject)-> Data? {
        
        let coercedobj = JSONSerializableObjectForObject(obj)
        var error : NSError? = nil
        var data : Data? = nil
        
        if JSONSerialization.isValidJSONObject(obj) {
            do {
                data = try JSONSerialization.data(withJSONObject: coercedobj, options: .prettyPrinted)
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
            print("Error parsing the json: \(error)")
        }
        
        return data
    }
    
    /**
     JSONSerializableObjectForObject: Function checks & converts data into approved data types for JSON
     
     :param: obj type AnyObject
     :returns: an AnyObject that has been verified and cleaned
     */
    fileprivate func JSONSerializableObjectForObject(_ obj: AnyObject)-> AnyObject {
        
        if JSONSerialization.isValidJSONObject(obj) {
            return obj
        }
        
        // Apple Documentation: "All objects need to be instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull"
        if (obj is NSString || obj is NSNumber || obj is NSNull) {
            return obj
        }
        
        // recurse through collections and serialize each object
        if obj is NSArray {
            let a = NSMutableArray()
            let objects = obj as! NSArray
            for item in objects {
                a.add(JSONSerializableObjectForObject(item as AnyObject))
            }
            return a as NSArray
        }
        
        if obj is NSDictionary {
            let dict = NSMutableDictionary()
            let objects = obj as! NSDictionary
            
            for key in objects.keyEnumerator() {
                var stringKey : NSString?
                if !((key as AnyObject) is NSString) {
                    stringKey = (key as AnyObject).description as NSString?
                    print("warning: property keys should be strings. got: \(stringKey)")
                } else {
                    stringKey = NSString(string: key as! NSString)
                }
                if stringKey != nil {
                    let v : AnyObject = JSONSerializableObjectForObject(objects[stringKey!]! as AnyObject)
                    dict[stringKey!] = v
                }
            }
            return dict
        }
        
        if obj is Date {
            return obj.timeIntervalSince1970 as AnyObject
        }
        
        let s = obj.description
        return s as AnyObject
    }
    
}
