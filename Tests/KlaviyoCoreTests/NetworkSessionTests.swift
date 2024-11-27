//
//  NetworkSessionTests.swift
//
//
//  Created by Noah Durell on 11/18/22.
//

@testable import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
class NetworkSessionTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() async throws {
        urlSession = nil
    }

    func testDefaultUserAgent() async {
        let userAgent = await defaultUserAgent()
        assertSnapshot(of: userAgent, as: .dump)
    }

    func testCreateEmphemeralSesionHeaders() async {
        let userAgent = await defaultUserAgent()
        assertSnapshot(of: createEmphemeralSession(userAgent: userAgent).configuration.httpAdditionalHeaders, as: .dump)
    }

    func testSessionDataTask() async throws {
        URLProtocolOverrides.protocolClasses = [SimpleMockURLProtocol.self]
        let session = NetworkSession.production
        let sampleRequest = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(.test), uuid: environment.uuid().uuidString)
        let (data, response) = try await session.data(sampleRequest.urlRequest())

        assertSnapshot(of: data, as: .dump)
        assertSnapshot(of: response, as: .dump)
    }
}
