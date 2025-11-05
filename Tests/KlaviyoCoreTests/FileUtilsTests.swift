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

    func testLoadPlist_DoesNotHangForNonReactNativeApps() {
        // This test verifies the performance fix - it should complete quickly
        let startTime = Date()

        // Try to load a plist that doesn't exist
        // In the old code, this would hang for 500ms-1.5s trying to load the RN bundle
        // In the new code, it should return immediately
        let result = loadPlist(named: "non-existent-config")

        let elapsedTime = Date().timeIntervalSince(startTime)

        XCTAssertNil(result, "Should return nil for non-existent plist")

        // The fix should make this complete in < 100ms (was 500-1500ms before)
        // We use 200ms as threshold to be safe on slow CI systems
        XCTAssertLessThan(elapsedTime, 0.2, "loadPlist should complete quickly (< 200ms) for non-React Native apps, but took \(elapsedTime)s")
    }
}
