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

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testProfilePayload() throws {
        let profile = Klaviyo.Profile.test
        let data = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload.Profile(profile: profile, anonymousId: "foo")
        var payload = KlaviyoAPI.KlaviyoRequest.KlaviyoEndpoint.CreateProfilePayload(data: data)
        assertSnapshot(matching: payload, as: .json(encoder))

    }

}
