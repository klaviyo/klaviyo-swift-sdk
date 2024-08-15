//
//  KlaviyoAPITests.swift
//
//
//  Created by Noah Durell on 11/16/22.
//

import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
final class KlaviyoAPITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        environment = KlaviyoEnvironment.test()
    }

    func testInvalidURL() async throws {
        environment.apiURL = ""

        await sendAndAssert(with: KlaviyoRequest(
            apiKey: "foo",
            endpoint: .createProfile(CreateProfilePayload(data: .test)))
        ) { result in
            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .description)
            default:
                XCTFail("Expected url failure")
            }
        }
    }

    func testEncodingError() async throws {
        environment.encodeJSON = { _ in throw EncodingError.invalidValue("foo", .init(codingPath: [], debugDescription: "invalid"))
        }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)))
        await sendAndAssert(with: request) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected encoding error.")
            }
        }
    }

    func testNetworkError() async throws {
        environment.networkSession = { NetworkSession.test(data: { _ in
            throw NSError(domain: "network error", code: 0)
        }) }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)))
        await sendAndAssert(with: request) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testInvalidStatusCode() async throws {
        environment.networkSession = { NetworkSession.test(data: { _ in
            (Data(), .non200Response)
        }) }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)))
        await sendAndAssert(with: request) { result in

            switch result {
            case let .failure(error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithProfile() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(CreateProfilePayload(data: .test)))
        await sendAndAssert(with: request) { result in

            switch result {
            case let .success(data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithEvent() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createEvent(CreateEventPayload(data: CreateEventPayload.Event(name: "test"))))
        await sendAndAssert(with: request) { result in
            switch result {
            case let .success(data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func testSuccessfulResponseWithStoreToken() async throws {
        environment.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(.test))
        await sendAndAssert(with: request) { result in

            switch result {
            case let .success(data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

    func sendAndAssert(with request: KlaviyoRequest,
                       assertion: (Result<Data, KlaviyoAPIError>) -> Void) async {
        let result = await KlaviyoAPI().send(request, 0)
        assertion(result)
    }
}
