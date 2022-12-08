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
        environment = KlaviyoEnvironment.test()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        LoggerClient.lastLoggedMessage = nil
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
    
}
