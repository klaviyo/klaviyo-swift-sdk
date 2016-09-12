import UIKit
import XCTest
@testable import KlaviyoSwift

class Tests: XCTestCase {
    var klaviyo: Klaviyo!
    
    // this is called after each invocation of the test method
    override func setUp() {
        super.setUp()
        Klaviyo.setupWithPublicAPIKey("wbg7GT")
        klaviyo = Klaviyo.sharedInstance
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        XCTAssert(true, "Pass")
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
    
    }
    
    // Verify that '$anonymous' payload exists within any and all payloads
    func testAnonymousKey() {
    
    }
    
    // Push tokens should be nil if user does not have push enabled
    func testPushNotificationOff() {
    
    }
    // test constructed payloads/dicts of the push & anonymous functionality
    
    
    
    // This is the code format for implementing performance tests
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
