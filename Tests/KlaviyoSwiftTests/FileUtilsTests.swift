//
//  FileUtilsTests.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/29/22.
//

import XCTest
@testable import KlaviyoSwift

class FileUtilsTests: XCTestCase {
    var dataToWrite: Data? = nil
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
}

