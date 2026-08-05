// Tests/KlaviyoCoreTests/PushTokenDataTests.swift
import XCTest
@testable import KlaviyoCore

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
