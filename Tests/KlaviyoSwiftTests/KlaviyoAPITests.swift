//
//  KlaviyoAPITests.swift
//
//
//  Created by Noah Durell on 11/16/22.
//

import XCTest
import SnapshotTesting
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift


@MainActor
final class KlaviyoAPITests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        environment = KlaviyoEnvironment.test()
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testInvalidURL() async throws {
        environment.analytics.apiURL = ": : ::"
        
        await sendAndAssert(with: .init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .test, anonymousId: "foo"))))) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .description)
            default:
                XCTFail("Expected url failure")
            }
        }
        
    }
    
    func testEncodingError() async throws {
        environment.analytics.encodeJSON = { _ in throw EncodingError.invalidValue("foo", .init(codingPath: [], debugDescription: "invalid"))
        }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        await sendAndAssert(with: request)  { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected encoding error.")
            }
        }
    }
    
    func testNetworkError() async throws {
        environment.analytics.networkSession = { NetworkSession.test(data: { request in
            throw NSError(domain: "network error", code: 0)
        }) }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        await sendAndAssert(with: request)  { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testInvalidStatusCode() async throws {
        environment.analytics.networkSession = { NetworkSession.test(data: { request in
            return (Data(), .non200Response)
        }) }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        await sendAndAssert(with: request){ result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testSuccessfulResponseWithProfile() async throws {
        environment.analytics.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        await sendAndAssert(with: request){ result in
            
            switch result {
            case .success(let data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testSuccessfulResponseWithEvent() async throws {
        environment.analytics.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        }) }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createEvent(.init(data: .init(event: .test))))
        await sendAndAssert(with: request){ result in
            
            switch result {
            case .success(let data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testSuccessfulResponseWithStoreToken() async throws {
        environment.analytics.networkSession = { NetworkSession.test(data: { request in
            assertSnapshot(matching: request, as: .dump)
            return (Data(), .validResponse)
        })}
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .storePushToken(.test))
        await sendAndAssert(with: request){ result in
            
            switch result {
            case .success(let data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func sendAndAssert(with request: KlaviyoAPI.KlaviyoRequest,
                       assertion: (Result<Data, KlaviyoAPI.KlaviyoAPIError>) -> Void) async {
        
        let result = await KlaviyoAPI().send(request)
        assertion(result)
    }
    
}
