import UIKit
import XCTest
@testable import KlaviyoSwift

class Tests: XCTestCase {
    var klaviyo: Klaviyo!
    
    // this is called after each invocation of the test method
    override func setUp() {
        super.setUp()
        Klaviyo.setupWithPublicAPIKey(apiKey: "wbg7GT")
        klaviyo = Klaviyo.sharedInstance
        environment = KlaviyoEnvironment.test
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        LoggerClient.lastLoggedMessage = nil
    }
    
    func testAPIKeyExists() {
        XCTAssertNotNil(klaviyo.apiKey, "API Key should not be nil after setup")
    }

    // Sanity check to verify any local host routes don't get deployed
    func testServerProdURL() {
        let prodServerURL = "https://a.klaviyo.com/api"
        XCTAssertEqual(prodServerURL, klaviyo.KlaviyoServerURLString, "Production server url should be used")
    }
    
    // Verify that 'identify' is called on app launch with the anonymous payload
    func testAnonymousUserIdentifiedOnAppLaunch() {
        let customerProperties = klaviyo.updatePropertiesDictionary(propDictionary: nil)
        XCTAssertNotNil(customerProperties[klaviyo.CustomerPropertiesIDDictKey], "anonymous ID should not be nil")
        let anonString = customerProperties[klaviyo.CustomerPropertiesIDDictKey] as? String
        XCTAssertNotNil(anonString, "anonymous ID should be a string")
        XCTAssertEqual(anonString!, klaviyo.iOSIDString, "anonymous ID should equal iOS String")
    }
    
    func testUserEmailIsSaved() {
        // save the user's email address
        let testEmail = "testemail@klaviyo.com"
        klaviyo.setUpUserEmail(userEmail: testEmail)
        
        // grab the cleaned payload when no further info is provided (i.e. a user tracks an event without customer data)
        let dict = klaviyo.updatePropertiesDictionary(propDictionary: nil)
        let email = dict[klaviyo.KLPersonEmailDictKey] as? String
        
        // verify the email is included even if not provided at the trackEvent level
        XCTAssertNotNil(email, "Email should exist if setupUserEmail has been called")
        XCTAssertEqual(testEmail, email, "email should match the one saved by the user")
    }
    
    // If a user passes in an email, that should get used in the payload and should override the saved address
    func testSetupEmailIsOverridden() {
        let testEmail = "testemail@klaviyo.com"
        klaviyo.setUpUserEmail(userEmail: testEmail)
        let newEmail = "mynewemail@klaviyo.com"
        let overrideDict: NSMutableDictionary = [klaviyo.KLPersonEmailDictKey: newEmail]
        let payload = klaviyo.updatePropertiesDictionary(propDictionary: overrideDict)
        let payloadEmail = payload[klaviyo.KLPersonEmailDictKey] as? String

        XCTAssertNotNil(payloadEmail, "email should not be nil")
        XCTAssertEqual(payloadEmail, newEmail, "new email should be used in payload")
        XCTAssertNotEqual(testEmail, payloadEmail, "payload email should not use initial email")
        
    }
    

    // Verify that '$anonymous' payload exists within any and all payloads and persists between calls to track
    func testAnonymousKey() {
        let dict = klaviyo.updatePropertiesDictionary(propDictionary: nil)
        let emailDict: NSMutableDictionary = [klaviyo.KLPersonEmailDictKey: "testemail@gmail.com"]
        let nonAnonymous = klaviyo.updatePropertiesDictionary(propDictionary: emailDict)
        let anonymous2 = nonAnonymous[klaviyo.CustomerPropertiesIDDictKey] as? String
        let anonymous = dict[klaviyo.CustomerPropertiesIDDictKey] as? String
        XCTAssertNotNil(anonymous, "Anonymous key should always exist in an unknown payload")
        XCTAssertNotNil(anonymous2, "Anonymous key should exist when email is included")
        XCTAssertEqual(anonymous, anonymous2, "Anonymous ID should be the same")
    }
    
    // Push tokens should be nil if user does not have push enabled
    func testPushNotificationOff() {
        let isRegisteredForPush = UIApplication.shared.isRegisteredForRemoteNotifications

        if !isRegisteredForPush {
            let apn = klaviyo.apnDeviceToken
            XCTAssertNil(apn, "push token should be nil if not registered for push")
        } else {
            XCTAssertNotNil(klaviyo.apnDeviceToken, "push token should exist if registered")
        }
    }
    
    func testTrackEventWithNoApiKey() {
        klaviyo.apiKey = nil
        
        klaviyo.trackEvent(eventName: "foo")
        
        XCTAssertEqual(LoggerClient.lastLoggedMessage, "Track event called before API key was set.")
        
    }
    
    func testTrackPersonWithNoApiKey() {
        klaviyo.apiKey = nil
        
        let emailDict: NSMutableDictionary = [klaviyo.KLPersonEmailDictKey: "testemail@gmail.com"]
        
        klaviyo.trackPersonWithInfo(personDictionary: emailDict)
        
        XCTAssertEqual(LoggerClient.lastLoggedMessage, "Track person called before API key was set.")
        
    }
    
}
