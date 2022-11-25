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
        analytics: AnalyticsEnvironment.test
    )
}

extension AnalyticsEnvironment {
    static let test = AnalyticsEnvironment(
        networkSession: NetworkSession.test(),
        apiURL: "dead_beef",
        encodeJSON: { _ in TEST_RETURN_DATA},
        uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
        date: { Date(timeIntervalSince1970: 1_234_567_890) }
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

extension NetworkSession {
    static let successfulRepsonse = HTTPURLResponse(url: TEST_URL, statusCode: 200, httpVersion: nil, headerFields: nil)
    static let DEFAULT_CALLBACK: @Sendable (URLRequest, @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> Void = { request , callback in
        callback(Data(), successfulRepsonse, nil)
    }
    static func test(callback: @escaping @Sendable (URLRequest, @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> Void = DEFAULT_CALLBACK) -> NetworkSession {
       return NetworkSession(dataTask: callback)
    }
}

