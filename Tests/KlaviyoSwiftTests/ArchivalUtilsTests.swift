//
//  ArchivalUtilsTests.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/26/22.
//

@testable import KlaviyoSwift
import KlaviyoCore
import XCTest

class ArchivalUtilsTests: XCTestCase {
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

    func testArchiveUnarchive() throws {
        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)

        XCTAssert(wroteToFile)
        XCTAssertEqual(ARCHIVED_RETURNED_DATA, dataToWrite)
    }

    func testArchiveFails() throws {
        environment.archiverClient.archivedData = { _, _ in throw FakeFileError.fake }
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
        environment.dataFromUrl = { _ in throw FakeFileError.fake }

        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)

        XCTAssertNil(archiveResult)
    }

    func testUnarchiveUnarchiveFails() throws {
        environment.archiverClient.unarchivedMutableArray = { _ in throw FakeFileError.fake }

        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)

        XCTAssertNil(archiveResult)
    }

    func testUnarchiveUnableToRemoveFile() throws {
        var firstCall = true
        environment.fileClient.fileExists = { _ in
            if firstCall {
                firstCall = false
                return true
            }
            return false
        }
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)

        XCTAssertEqual(SAMPLE_DATA, archiveResult)
        XCTAssertFalse(removedFile)
    }

    func testUnarchiveWhereFileDoesNotExist() throws {
        environment.fileClient.fileExists = { _ in false }
        let archiveResult = unarchiveFromFile(fileURL: TEST_URL)

        XCTAssertNil(archiveResult)
        XCTAssertFalse(removedFile)
    }
}

class ArchivalSystemTest: XCTestCase {
    let TEST_URL = filePathForData(apiKey: "foo", data: "people")

    override func setUpWithError() throws {
        try? FileManager.default.removeItem(atPath: TEST_URL.path)
    }

    /* This will attempt to actually archive and unarchive a queue. */
    func testArchiveUnarchive() {
        archiveQueue(queue: SAMPLE_DATA, to: TEST_URL)
        let result = unarchiveFromFile(fileURL: filePathForData(apiKey: "foo", data: "people"))

        XCTAssertEqual(SAMPLE_DATA, result)
    }
}
