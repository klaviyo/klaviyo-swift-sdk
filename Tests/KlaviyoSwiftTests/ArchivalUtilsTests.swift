//
//  ArchivalUtilsTests.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/26/22.
//

import XCTest
@testable import KlaviyoSwift

public enum FakeFileError: Error {
    case fake
}

let ARCHIVED_RETURNED_DATA = Data()
let SAMPLE_DATA: NSMutableArray = [
    [
        "foo": "bar"
    ]

]
let TEST_URL = URL(string: "fake_url")
let TEST_RETURN_DATA = Data()

extension ArchiverClient {
    static let test = ArchiverClient(archivedData: { _, _ in return ARCHIVED_RETURNED_DATA })
}

extension KlaviyoEnvironment {
    static var testURL = { (_:String) in TEST_URL }
    static let test = KlaviyoEnvironment(
        archiverClient: ArchiverClient.test,
        fileClient: FileClient.test,
        url: testURL,
        data: { _ in return TEST_RETURN_DATA }
    )
}

extension FileClient {
    static let test = FileClient(
        write: { _,_ in },
        fileExists: { _ in return true },
        removeItem: { _ in },
        libraryDirectory: { "deadbeef" }
    )
}

class ArchivalUtilsTests: XCTestCase {
    
    var dataToWrite: Data? = nil
    var wroteToFile = false

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test
        environment.fileClient.write = { [weak self] data, _ in
            self?.wroteToFile = true
            self?.dataToWrite = data
        }
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        wroteToFile = false
        dataToWrite = nil
    }

    func testArchiveUnarchive() throws {

        archiveQueue(queue: SAMPLE_DATA, to: URL(string: "foo")!)
        
        XCTAssert(wroteToFile)
        XCTAssertEqual(ARCHIVED_RETURNED_DATA, dataToWrite)
    }
    
    func testArchiveFails() throws {
        environment.archiverClient.archivedData = { _,_ in throw FakeFileError.fake }
        archiveQueue(queue: SAMPLE_DATA, to: URL(string: "foo")!)
        
        XCTAssertFalse(wroteToFile)
        XCTAssertNil(dataToWrite)
    }

    func testArchiveWriteFails() throws {
        environment.fileClient.write = { _, _ in throw FakeFileError.fake }
        archiveQueue(queue: SAMPLE_DATA, to: URL(string: "foo")!)
        
        XCTAssertFalse(wroteToFile)
        XCTAssertNil(dataToWrite)
    }
    
    func testUnarchive() throws {
        unarchiveFromFile(filePath: "foo")
        
        
    }

}
