//
//  File.swift
//  
//
//  Created by Noah Durell on 11/18/22.
//

import XCTest
@testable import KlaviyoSwift
import SnapshotTesting

class NetworkSessionTests: XCTestCase {
    override func setUpWithError() throws {

        environment = KlaviyoEnvironment.test
    }
    func testDefaultUserAgent() {
        assertSnapshot(matching: defaultUserAgent, as: .dump)
    }
    func testCreateEmphemeralSesionHeaders() {
        assertSnapshot(matching: createEmphemeralSession().configuration.httpAdditionalHeaders, as: .dump)
    }
    
    func testSessionDataTask() throws {
        URLProtocolOverrides.protocolClasses = [SimpleMockURLProtocol.self]
        let session = NetworkSession.production
        let expectation = expectation(description: "wait for request")
        let sampleRequest = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .storePushToken(.test))
        session.dataTask(try sampleRequest.urlRequest()) { data, response, error in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 0.5)
    }
}

extension URLSession {
    
}
