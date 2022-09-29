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
let TEST_URL = URL(string: "fake_url")!
let TEST_RETURN_DATA = Data()

extension ArchiverClient {
    static let test = ArchiverClient(
        archivedData: { _, _ in ARCHIVED_RETURNED_DATA },
        unarchivedMutableArray: { _ in SAMPLE_DATA }
    )
}

extension KlaviyoEnvironment {
    static var testURL = { (_:String) in TEST_URL }
    static let test = KlaviyoEnvironment(
        archiverClient: ArchiverClient.test,
        fileClient: FileClient.test,
        url: testURL,
        data: { _ in TEST_RETURN_DATA }
    )
}

extension FileClient {
    static let test = FileClient(
        write: { _,_ in },
        fileExists: { _ in return true },
        removeItem: { _ in },
        libraryDirectory: { TEST_URL }
    )
}

class ArchivalUtilsTests: XCTestCase {
    
    var dataToWrite: Data? = nil
    var wroteToFile = false
    var removedFile = false

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test
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

    func testArchiveUnarchive() throws {

        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)
        
        XCTAssert(wroteToFile)
        XCTAssertEqual(ARCHIVED_RETURNED_DATA, dataToWrite)
    }
    
    func testArchiveFails() throws {
        environment.archiverClient.archivedData = { _,_ in throw FakeFileError.fake }
        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)
        
        XCTAssertFalse(wroteToFile)
        XCTAssertNil(dataToWrite)
    }

    func testArchiveWriteFails() throws {
        environment.fileClient.write = { _, _ in throw FakeFileError.fake }
        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)
        
        XCTAssertFalse(wroteToFile)
        XCTAssertNil(dataToWrite)
    }
    
    func testUnarchive() throws {
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)
        
        XCTAssertEqual(SAMPLE_DATA, archiveResult)
        XCTAssertTrue(removedFile)
    }
    
    func testUnarchiveInvalidData() throws {
        environment.data = { _ in throw FakeFileError.fake }
        
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)
        
        XCTAssertNil(archiveResult)
    }
    
    func testUnarchiveUnarchiveFails() throws {
        environment.archiverClient.unarchivedMutableArray = { _ in throw FakeFileError.fake }
        
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)
        
        XCTAssertNil(archiveResult)
    }
    func testUnarchiveUnableToRemoveFile() throws {
        environment.fileClient.fileExists = { _ in false }
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)
        
        XCTAssertEqual(SAMPLE_DATA, archiveResult)
        XCTAssertFalse(removedFile)
    }

}

class ArchivalSystemTest: XCTestCase {
 
    let TEST_URL = filePathForData(apiKey: "foo", data: "people")
    /* This will attempt to actually archive and unarchive a queue. */
    func testArchiveUnarchive() {
        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)
        let result = unarchiveFromFile(fileURL: filePathForData(apiKey: "foo", data: "people"))
        
        XCTAssertEqual(SAMPLE_DATA, result)
    }
}
