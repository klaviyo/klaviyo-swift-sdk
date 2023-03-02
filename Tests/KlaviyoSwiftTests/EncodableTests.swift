//
//  EncodableTests.swift
//  
//
//  Created by Noah Durell on 11/14/22.
//

import XCTest
import SnapshotTesting
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

final class EncodableTests: XCTestCase {
    let testEncoder = encoder
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testProfilePayload() throws {
        let profile = Profile.test
        let data = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload.Profile(profile: profile, anonymousId: "foo")
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(data: data)
        assertSnapshot(matching: payload, as: .json(encoder))

    }
    
    func testEventPayload() throws {
        let event = Event.test
        let createEventPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: .init(event: event))
        assertSnapshot(matching: createEventPayload, as: .json(encoder))
    }
    
    func testTokenPayload() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            token: "foo",
            properties: .init(anonymousId: "foo",
                              pushToken: "foo",
                              email: "foo",
                              phoneNumber: "foo")
        )
        assertSnapshot(matching: tokenPayload, as: .json(encoder))
    }
    
    func testKlaviyoState() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            token: "foo",
            properties: .init(anonymousId: "foo",
                              pushToken: "foo",
                              email: "foo",
                              phoneNumber: "foo")
        )
        let request = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .storePushToken(tokenPayload))
        let klaviyoState = KlaviyoState(email: "foo", anonymousId: "foo",
                                        phoneNumber: "foo", pushToken: "foo",
                                        queue: [request], requestsInFlight: [request])
        assertSnapshot(matching: klaviyoState, as: .json)
    }
    
    func testKlaviyoRequest() throws {
        let tokenPayload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            token: "foo",
            properties: .init(anonymousId: "foo",
                              pushToken: "foo",
                              email: "foo",
                              phoneNumber: "foo")
        )
        let request = KlaviyoAPI.KlaviyoRequest(apiKey: "foo", endpoint: .storePushToken(tokenPayload))
        assertSnapshot(matching: request, as: .json)
    }

}
