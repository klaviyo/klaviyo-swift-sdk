@testable import KlaviyoCore
import XCTest

final class KlaviyoRequestTests: XCTestCase {
    func testURLRequestSetsAttemptHeader() throws {
        let request = KlaviyoRequest(endpoint: .registerPushToken("foo", .test))
        let attemptInfo = try RequestAttemptInfo(attemptNumber: 3, maxAttempts: 7)
        let urlRequest = try request.urlRequest(attemptInfo: attemptInfo)
        let header = urlRequest.value(forHTTPHeaderField: "X-Klaviyo-Attempt-Count")
        XCTAssertEqual(header, "3/7")
    }

    // MARK: - Priority

    func testDefaultPriorityIsStandard() {
        let request = KlaviyoRequest(endpoint: .registerPushToken("foo", .test))
        XCTAssertEqual(request.priority, .standard)
    }

    func testHighPriorityIsPreservedOnInit() {
        let request = KlaviyoRequest(endpoint: .registerPushToken("foo", .test), priority: .high)
        XCTAssertEqual(request.priority, .high)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripPreservesPriority() throws {
        let original = KlaviyoRequest(endpoint: .registerPushToken("foo", .test), priority: .high)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KlaviyoRequest.self, from: data)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testDecodeLegacyPayloadWithoutPriorityDefaultsToStandard() throws {
        // Simulate a queue entry persisted by an older SDK version that has no `priority` key.
        let original = KlaviyoRequest(endpoint: .registerPushToken("foo", .test))
        guard var encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original), options: []
        ) as? [String: Any] else {
            XCTFail("Encoded request is not a JSON object")
            return
        }
        encoded.removeValue(forKey: "priority")
        let legacyData = try JSONSerialization.data(withJSONObject: encoded)
        let decoded = try JSONDecoder().decode(KlaviyoRequest.self, from: legacyData)
        // Legacy payloads without a priority key should default to .standard
        XCTAssertEqual(decoded.priority, .standard)
    }
}

// MARK: - RequestPriority tests

final class RequestPriorityTests: XCTestCase {
    func testCodableRoundTrip() throws {
        for priority in [RequestPriority.standard, .high] {
            let data = try JSONEncoder().encode(priority)
            let decoded = try JSONDecoder().decode(RequestPriority.self, from: data)
            XCTAssertEqual(decoded, priority)
        }
    }

    func testRawValues() {
        XCTAssertEqual(RequestPriority.standard.rawValue, "standard")
        XCTAssertEqual(RequestPriority.high.rawValue, "high")
    }
}
