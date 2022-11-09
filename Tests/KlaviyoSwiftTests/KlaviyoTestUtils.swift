//
//  KlaviyoTestUtils.swift
//  KlaviyoSwiftTests
//
//  Created by Noah Durell on 9/30/22.
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
    static var lastLog: String?
    static let test = KlaviyoEnvironment(
        archiverClient: ArchiverClient.test,
        fileClient: FileClient.test,
        data: { _ in TEST_RETURN_DATA },
        logger: LoggerClient.test,
        networkSession: NetworkSession.production,
        apiURL: "dead_beef"
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

extension LoggerClient {
    static var lastLoggedMessage: String?
    static let test = LoggerClient { message in
        lastLoggedMessage = message
    }
}

