//
//  KlaviyoAPITests.swift
//
//
//  Created by Noah Durell on 11/16/22.
//

@testable import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
final class KlaviyoAPITests: XCTestCase {
    var networkSession: NetworkSession!
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        networkSession = NetworkSession.test()
    }

    func testInvalidURL() async throws {
        environment.apiURL = { "" }

        await sendAndAssert(with: KlaviyoRequest(
            apiKey: "foo",
            endpoint: .createProfile(CreateProfilePayload(data: .test)), uuid: environment.uuid().uuidString),
        networkSession: networkSession) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(of: error, as: .description)
            default:
                XCTFail("Expected url failure")
            }
        }
    }

    func testEncodingError() async throws {
        environment.encodeJSON = { _ in throw EncodingError.invalidValue("foo", .init(codingPath: [], debugDescription: "invalid"))
        }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(of: error, as: .dump)
            default:
                XCTFail("Expected encoding error.")
            }
        }
    }

    func testNetworkError() async throws {
        networkSession = NetworkSession.test(data: { _ in
            throw NSError(domain: "network error", code: 0)
        })
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(of: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testInvalidStatusCode() async throws {
        networkSession = NetworkSession.test(data: { _ in
            (Data(), .non200Response)
        })
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(of: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithProfile() async throws {
        networkSession = NetworkSession.test(data: { request in
            assertSnapshot(of: request, as: .dump)
            return (Data(), .validResponse)
        })
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in

            switch result {
            case let .success(data):
                assertSnapshot(of: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithEvent() async throws {
        networkSession = NetworkSession.test(data: { request in
            assertSnapshot(of: request, as: .dump)
            return (Data(), .validResponse)
        })
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createEvent(CreateEventPayload(data: CreateEventPayload.Event(name: "test", appContextInfo: .test))), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in
            switch result {
            case let .success(data):
                assertSnapshot(of: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithStoreToken() async throws {
        let networkSession = NetworkSession.test(data: { request in
            assertSnapshot(of: request, as: .dump)
            return (Data(), .validResponse)
        })
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(.test), uuid: environment.uuid().uuidString)
        await sendAndAssert(with: request, networkSession: networkSession) { result in

            switch result {
            case let .success(data):
                assertSnapshot(of: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func sendAndAssert(with request: KlaviyoRequest,
                       networkSession: NetworkSession,
                       assertion: (Result<Data, KlaviyoAPIError>) -> Void) async {
        let result = await KlaviyoAPI().send(networkSession, request, 0)
        assertion(result)
    }
}
