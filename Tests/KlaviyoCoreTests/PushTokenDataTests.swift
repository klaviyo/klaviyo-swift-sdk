//
//  PushTokenDataTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 6/16/26.
//

@testable import KlaviyoCore
import XCTest

final class PushTokenDataTests: XCTestCase {
    func testPushTokenDataRoundTripsThroughCodable() throws {
        let data = PushTokenData(
            pushToken: "tok-123",
            pushEnablement: .authorized,
            pushBackground: .available,
            deviceData: DeviceMetadata(context: .test)
        )
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(PushTokenData.self, from: encoded)
        XCTAssertEqual(decoded, data)
    }
}
