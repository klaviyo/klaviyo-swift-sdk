//
//  LegacyStateTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class LegacyStateTests: XCTestCase {
    private func decodeLegacyState(_ json: String) throws -> LegacyState {
        try JSONDecoder().decode(LegacyState.self, from: Data(json.utf8))
    }

    func testDecodesNewFormatNestedIdentity() throws {
        let decoded = try decodeLegacyState("""
        {"apiKey":"k","identity":{"email":"a@b.com","anonymousId":"anon"},"queue":[]}
        """)
        XCTAssertEqual(decoded.apiKey, "k")
        XCTAssertEqual(decoded.identity.email, "a@b.com")
        XCTAssertEqual(decoded.identity.anonymousId, "anon")
    }

    func testDecodesLegacyTopLevelIdentity() throws {
        let decoded = try decodeLegacyState("""
        {"apiKey":"k","email":"a@b.com","anonymousId":"anon","queue":[]}
        """)
        XCTAssertEqual(decoded.identity.email, "a@b.com")
        XCTAssertEqual(decoded.identity.anonymousId, "anon")
    }

    func testDecodesQueueOnlyBlobWithEmptyIdentity() throws {
        let decoded = try decodeLegacyState("{\"queue\":[]}")
        XCTAssertNil(decoded.apiKey)
        XCTAssertNil(decoded.identity.email)
    }
}
