//
//  NetworkSessionTests.swift
//
//
//  Created by Noah Durell on 11/18/22.
//

@testable import KlaviyoSwift
import SnapshotTesting
import XCTest

@MainActor
class NetworkSessionTests: XCTestCase {
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    func testDefaultUserAgent() {
        assertSnapshot(matching: defaultUserAgent, as: .dump)
    }

    func testCreateEmphemeralSesionHeaders() {
        assertSnapshot(matching: createEmphemeralSession().configuration.httpAdditionalHeaders, as: .dump)
    }

    func testSessionDataTask() async throws {
        URLProtocolOverrides.protocolClasses = [SimpleMockURLProtocol.self]
        let session = NetworkSession.production
        let sampleRequest = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .storePushToken(.test))
        let (data, response) = try await session.data(sampleRequest.urlRequest())

        assertSnapshot(matching: data, as: .dump)
        assertSnapshot(matching: response, as: .dump)
    }
}
