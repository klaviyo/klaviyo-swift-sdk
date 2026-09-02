//
//  KlaviyoStateTests.swift
//
//
//  Created by Noah Durell on 12/1/22.
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import XCTest

final class KlaviyoStateTests: XCTestCase {
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
    }

    // NOTE: the former disk-load and save tests (`testLoadNewKlaviyoState`,
    // `testStateFileExistsInvalidData`, `testStateFileExistsInvalidJSON`,
    // `testValidStateFileExists`, `testSaveKlaviyoStateWithMissingApiKeyLogsError`) were
    // removed in Task 5. `KlaviyoState` is no longer `Codable` and the persistence
    // functions (`loadKlaviyoStateFromDisk`, `saveKlaviyoState`, etc.) were deleted.
    // The queue-file round-trip is covered by QueueStoreTests.

    // MARK: test background and authorization states

    func testBackgroundStates() {
        let backgroundStates = [
            UIBackgroundRefreshStatus.available: PushBackground.available,
            .denied: .denied,
            .restricted: .restricted
        ]

        for (status, expecation) in backgroundStates {
            XCTAssertEqual(PushBackground.create(from: status), expecation)
        }

        // Fake value to test availability
        XCTAssertEqual(PushBackground.create(from: UIBackgroundRefreshStatus(rawValue: 20)!), .available)
    }

    @available(iOS 14.0, *)
    func testPushEnablementStates() {
        let enablementStates = [
            UNAuthorizationStatus.authorized: PushEnablement.authorized,
            .denied: .denied,
            .ephemeral: .ephemeral,
            .notDetermined: .notDetermined,
            .provisional: .provisional
        ]

        for (status, expecation) in enablementStates {
            XCTAssertEqual(PushEnablement.create(from: status), expecation)
        }

        // Fake value to test availability
        XCTAssertEqual(PushEnablement.create(from: UNAuthorizationStatus(rawValue: 50)!), .notDetermined)
    }

    // NOTE: queue capacity / eviction is now owned by the Core `QueueStore` (see
    // `QueueStore.enqueue` / `evictIfAtCapacity`), which has its own parity tests. The former
    // `KlaviyoState`-level eviction tests moved there along with the queue backing.

    // MARK: - KlaviyoRequest encode/decode

    /// Builds a token request with a specific id and enqueue timestamp for request round-trip tests.
    private func makeTokenRequest(id: String, enqueuedAt: Date) -> KlaviyoRequest {
        let tokenPayload = PushTokenPayload(
            pushToken: "token",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: nil, phoneNumber: nil, anonymousId: "anon")
        )
        return KlaviyoRequest(
            id: id,
            endpoint: .registerPushToken(TEST_API_KEY, tokenPayload),
            enqueuedAt: enqueuedAt
        )
    }

    func testKlaviyoRequestEncodeDecodeRoundTripPreservesEnqueuedAt() throws {
        // A current request must encode AND decode its enqueuedAt (verifies Encodable is intact
        // alongside the custom Decodable init).
        let request = makeTokenRequest(id: "current", enqueuedAt: Date(timeIntervalSince1970: 999))
        let data = try KlaviyoEnvironment.encoder.encode(request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(KlaviyoRequest.self, from: data)

        XCTAssertEqual(decoded.id, "current")
        XCTAssertEqual(
            decoded.enqueuedAt, Date(timeIntervalSince1970: 999), "Present enqueuedAt must round-trip"
        )
    }

    func testKlaviyoRequestDecodesMissingEnqueuedAtAsDistantPast() throws {
        // Strip `enqueuedAt` to simulate a request persisted before the field existed
        // (e.g. carried across an app upgrade).
        let request = makeTokenRequest(id: "legacy", enqueuedAt: Date(timeIntervalSince1970: 999))
        let data = try KlaviyoEnvironment.encoder.encode(request)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "enqueuedAt")
        XCTAssertNil(json["enqueuedAt"], "Precondition: enqueuedAt must be absent from the legacy payload")
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Decoding must not throw on the missing key, and enqueuedAt must default to distantPast.
        let decoded = try decoder.decode(KlaviyoRequest.self, from: strippedData)
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertEqual(
            decoded.enqueuedAt,
            .distantPast,
            "A missing enqueuedAt must default to Date.distantPast"
        )
    }

    // NOTE: the former `testDecodesLegacyFlatIdentityJSON`, `testDecodesNewNestedIdentityJSON`,
    // and `testPersistedStateEncodesNoIdentityOrQueue` tests were removed in Task 5.
    // `KlaviyoState` is no longer `Codable`. The legacy decode path (flat/nested identity shapes)
    // is exercised via `LegacyStateMigration`, which decodes into `LegacyState` (not KlaviyoState).
}
