//
//  EncodableTests.swift
//  
//
//  Created by Noah Durell on 11/14/22.
//

import XCTest
import SnapshotTesting
@testable import KlaviyoSwift

final class EncodableTests: XCTestCase {
    let testEncoder = encoder
    override func setUpWithError() throws {
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testProfilePayload() throws {
        let profile = Klaviyo.Profile.test
        let data = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload.Profile(profile: profile, anonymousId: "foo")
        let payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(data: data)
        assertSnapshot(matching: payload, as: .json(encoder))

    }
    
    func testEventPayload() throws {
        let event = Klaviyo.Event.test
        _ = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateEventPayload(data: event)
        assertSnapshot(matching: event, as: .json(encoder))
    }

}
