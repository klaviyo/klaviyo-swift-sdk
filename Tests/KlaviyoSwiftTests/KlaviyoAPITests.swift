//
//  KlaviyoAPITests.swift
//  
//
//  Created by Noah Durell on 11/16/22.
//

import XCTest
import SnapshotTesting
@testable import KlaviyoSwift


final class KlaviyoAPITests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        environment = KlaviyoEnvironment.test
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testInvalidURL() throws {
        environment.apiURL = ": : ::"
        
        KlaviyoAPI().post(.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .test, anonymousId: "foo"))))) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .description)
            default:
                XCTFail("Expected url failure")
            }
        }
        
    }
    
    func testEncodingError() throws {
        environment.encodeJSON = { _ in throw EncodingError.invalidValue("foo", .init(codingPath: [KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload.CodingKeys.data], debugDescription: "invalid"))
        }
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected encoding error.")
            }
        }
    }
    
    func testNetworkError() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            callback(nil, nil, NSError(domain: "network error", code: 0))
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testNilResponse() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            callback(nil, nil, nil)
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testInvalidStatusCode() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            callback(nil, .non200Response, nil)
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testMissingData() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            callback(nil, .validResponse, nil)
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .failure(let error):
                assertSnapshot(matching: error, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testSuccessfulResponseWithProfile() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            assertSnapshot(matching: request, as: .dump)
            callback(Data(), .validResponse, nil)
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createProfile(.init(data: .init(profile: .init(attributes: .init()), anonymousId: "foo"))))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .success(let data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }
    
    func testSuccessfulResponseWithEvent() throws {
        environment.networkSession = NetworkSession.test(callback: { request, callback in
            assertSnapshot(matching: request, as: .dump)
            callback(Data(), .validResponse, nil)
        })
        let request = KlaviyoAPI.KlaviyoRequest.init(apiKey: "foo", endpoint: .createEvent(.init(data: .test)))
        KlaviyoAPI().post(request) { result in
            
            switch result {
            case .success(let data):
                assertSnapshot(matching: data, as: .dump)
            default:
                XCTFail("Expected failure here.")
            }
        }
    }

}
