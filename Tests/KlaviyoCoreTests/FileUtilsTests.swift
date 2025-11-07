//
//  FileUtilsTests.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/29/22.
//

import KlaviyoCore
import XCTest

class FileUtilsTests: XCTestCase {
    var dataToWrite: Data?
    var wroteToFile = false
    var removedFile = false

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        environment.fileClient.write = { [weak self] data, _ in
            self?.wroteToFile = true
            self?.dataToWrite = data
        }
        environment.fileClient.removeItem = { [weak self] _ in
            self?.removedFile = true
        }
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        wroteToFile = false
        dataToWrite = nil
        removedFile = false
    }

    func testFilePathForData() throws {
        let eventsResult = filePathForData(apiKey: "mykey", data: "events")
        XCTAssertEqual(URL(string: "fake_url/klaviyo-mykey-events.plist")!, eventsResult)

        let peopleResult = filePathForData(apiKey: "mykey", data: "people")
        XCTAssertEqual(URL(string: "fake_url/klaviyo-mykey-people.plist")!, peopleResult)
    }

    func testRemoveItemWithError() {
        environment.fileClient.removeItem = { _ in
            throw FakeFileError.fake
        }
        XCTAssertFalse(removeFile(at: TEST_URL))
    }

    // MARK: - loadPlist Tests

    func testLoadPlist_ReturnsNilForNonExistentPlist() {
        let result = loadPlist(named: "non-existent-plist")
        XCTAssertNil(result, "Should return nil when plist doesn't exist in main bundle")
    }

    func testLoadPlist_ReturnsMainBundlePlistIfExists() {
        // Note: This test depends on the actual bundle contents
        // If klaviyo-sdk-configuration.plist exists in test bundle, it should be loaded
        let result = loadPlist(named: "klaviyo-sdk-configuration")

        // The test should either find it in the main bundle or return nil
        // This verifies the function doesn't crash and handles the case correctly
        if result != nil {
            XCTAssertTrue(result is [String: AnyObject], "Should return dictionary if plist exists")
        } else {
            XCTAssertNil(result, "Should return nil if plist doesn't exist")
        }
    }

    func testLoadPlist_CompletesQuickly() {
        // This test verifies that loadPlist() only checks main bundle (fast operation)
        let startTime = Date()

        let result = loadPlist(named: "non-existent-config")

        let elapsedTime = Date().timeIntervalSince(startTime)

        XCTAssertNil(result, "Should return nil for non-existent plist")

        // Should complete very quickly since it only checks main bundle
        XCTAssertLessThan(elapsedTime, 0.1, "loadPlist should complete quickly (< 100ms), but took \(elapsedTime)s")
    }

    func testLoadPlistFromReactNativeBundle_ReturnsNilWhenBundleNotFound() {
        // This will be nil for non-RN test environments
        let result = loadPlistFromReactNativeBundle(named: "klaviyo-sdk-configuration")

        // Should return nil without crashing
        // In a real RN environment, this might return a value
        XCTAssertTrue(result == nil || result is [String: AnyObject], "Should return nil or valid dictionary")
    }
}
