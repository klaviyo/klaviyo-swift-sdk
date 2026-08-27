//
//  LegacyStateTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class LegacyStateTests: XCTestCase {
    func testDecodesNewFormatNestedIdentity() throws {
        let json = Data("""
        {"apiKey":"k","identity":{"email":"a@b.com","anonymousId":"anon"},"queue":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(LegacyState.self, from: json)
        XCTAssertEqual(decoded.apiKey, "k")
        XCTAssertEqual(decoded.identity.email, "a@b.com")
        XCTAssertEqual(decoded.identity.anonymousId, "anon")
    }

    func testDecodesLegacyTopLevelIdentity() throws {
        let json = Data("""
        {"apiKey":"k","email":"a@b.com","anonymousId":"anon","queue":[]}
        """.utf8)
        let decoded = try JSONDecoder().decode(LegacyState.self, from: json)
        XCTAssertEqual(decoded.identity.email, "a@b.com")
        XCTAssertEqual(decoded.identity.anonymousId, "anon")
    }

    func testDecodesQueueOnlyBlobWithEmptyIdentity() throws {
        let json = Data("{\"queue\":[]}".utf8)
        let decoded = try JSONDecoder().decode(LegacyState.self, from: json)
        XCTAssertNil(decoded.apiKey)
        XCTAssertNil(decoded.identity.email)
    }
}
