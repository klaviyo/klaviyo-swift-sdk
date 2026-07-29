//
//  KlaviyoStateTests.swift
//
//
//  Created by Noah Durell on 12/1/22.
//

@testable import KlaviyoSwift
import Foundation
import KlaviyoCore
import SnapshotTesting
import XCTest

final class KlaviyoStateTests: XCTestCase {
    let TEST_EVENT = [
        "event": "$opened_push",
        "properties": [
            "prop1": "propValue"
        ],
        "customer_properties": [
            "foo": "bar"
        ]
    ] as [String: Any]

    let TEST_PROFILE = [
        "properties": [
            "foo2": "bar2"
        ]
    ]

    let TEST_INVALID_EVENT = [
        "properties": [
            "prop1": "propValue"
        ],
        "customer_properties": [
            "foo": "bar"
        ]
    ]
    let TEST_INVALID_PROFILE = [
        "garbage_key": [
            "foo": "bar"
        ]
    ]
    let TEST_INVALID_PROPERTIES_EVENT = [
        "properties": [
            1: "propValue"
        ] as [AnyHashable: String],
        "customer_properties": [
            "foo": "bar"
        ]
    ]

    let TEST_INVALID_CUSTOMER_PROPERTIES_EVENT = [
        "event": "$opened_push",
        "properties": [
            "fo": "propValue"
        ],
        "customer_properties": [
            1: "bar"
        ]
    ] as [String: Any]
    let TEST_INVALID_PROPERTIES_PROFILE = [
        "event": "$opened_push",
        "properties": [
            1: "propValue"
        ]
    ] as [String: Any]

    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    func testLoadNewKlaviyoState() throws {
        environment.fileClient.fileExists = { _ in false }
        environment.archiverClient.unarchivedMutableArray = { _ in [] }
        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testStateFileExistsInvalidData() throws {
        environment.fileClient.fileExists = { _ in
            true
        }
        environment.dataFromUrl = { _ in
            throw NSError(domain: "missing file", code: 1)
        }
        environment.archiverClient.unarchivedMutableArray = { _ in
            XCTFail("unarchivedMutableArray should not be called.")
            return []
        }

        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testStateFileExistsInvalidJSON() throws {
        environment.fileClient.fileExists = { _ in
            true
        }

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())
        environment.archiverClient.unarchivedMutableArray = { _ in
            XCTFail("unarchivedMutableArray should not be called.")
            return []
        }

        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testValidStateFileExists() throws {
        environment.fileClient.fileExists = { _ in
            true
        }
        environment.dataFromUrl = { _ in
            try! JSONEncoder().encode(KlaviyoState(
                apiKey: "foo",
                anonymousId: environment.uuid().uuidString,
                queue: [],
                requestsInFlight: []
            ))
        }

        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testFullKlaviyoStateEncodingDecodingIsEqual() throws {
        let event = Event.test
        let createEventPayload = CreateEventPayload(data: CreateEventPayload.Event(name: event.metric.name.value))
        let eventRequest = KlaviyoRequest(endpoint: .createEvent("foo", createEventPayload))

        let profile = Profile.test
        let payload = CreateProfilePayload(data: ProfilePayload(profile, anonymousId: "foo"))

        let profileRequest = KlaviyoRequest(endpoint: .createProfile("foo", payload))
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo")
        )
        let tokenRequest = KlaviyoRequest(endpoint: .registerPushToken("foo", tokenPayload))

        let state = KlaviyoState(apiKey: "key", queue: [tokenRequest, eventRequest, profileRequest])

        let encodedState = try KlaviyoEnvironment.production.encodeJSON(state)
        let decodedState: KlaviyoState = try KlaviyoEnvironment.production.decoder.decode(encodedState)

        XCTAssertEqual(decodedState, state)
    }

    func testSaveKlaviyoStateWithMissingApiKeyLogsError() {
        var savedMsg: String?
        environment.logger.error = { msg in savedMsg = msg }
        let state = KlaviyoState(queue: [])
        saveKlaviyoState(state: state)

        XCTAssertEqual(savedMsg, "Attempt to save state without an api key.")
    }

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

    // MARK: - enqueueRequest capacity / eviction

    func testEnqueueRequestEvictsOldestWhenAtCapacity() throws {
        // Arrange: build a state pre-loaded with exactly maxQueueSize requests.
        let tokenPayload = PushTokenPayload(
            pushToken: "token",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: nil, phoneNumber: nil, anonymousId: "anon")
        )
        let maxSize = StateManagementConstants.maxQueueSize

        var requests = (0..<maxSize).map { _ in
            KlaviyoRequest(id: UUID().uuidString, endpoint: .registerPushToken(TEST_API_KEY, tokenPayload))
        }

        let firstId = requests[0].id
        let secondId = requests[1].id

        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // The new request that should survive and land at the tail.
        let newRequest = KlaviyoRequest(
            id: UUID().uuidString, endpoint: .registerPushToken(TEST_API_KEY, tokenPayload)
        )

        // Act
        state.enqueueRequest(request: newRequest)

        // Assert: cap is held, oldest is gone, new request is at the tail, formerly-second is now first.
        XCTAssertEqual(state.queue.count, maxSize, "Queue count must equal maxQueueSize after eviction")
        XCTAssertFalse(state.queue.contains(where: { $0.id == firstId }), "Oldest request must be evicted")
        XCTAssertEqual(state.queue.last?.id, newRequest.id, "New request must be at the tail")
        XCTAssertEqual(state.queue.first?.id, secondId, "Formerly-second request must now be first")
    }

    func testEnqueueRequestBelowCapacityAppendsWithoutEviction() {
        // Arrange: state with one fewer than capacity.
        let tokenPayload = PushTokenPayload(
            pushToken: "token",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: nil, phoneNumber: nil, anonymousId: "anon")
        )
        let belowMax = StateManagementConstants.maxQueueSize - 1
        let existing = (0..<belowMax).map { _ in
            KlaviyoRequest(id: UUID().uuidString, endpoint: .registerPushToken(TEST_API_KEY, tokenPayload))
        }
        let firstId = existing[0].id
        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: existing)

        let newRequest = KlaviyoRequest(
            id: UUID().uuidString, endpoint: .registerPushToken(TEST_API_KEY, tokenPayload)
        )

        // Act
        state.enqueueRequest(request: newRequest)

        // Assert: count grew to maxQueueSize, oldest is untouched, new is at tail.
        XCTAssertEqual(state.queue.count, StateManagementConstants.maxQueueSize)
        XCTAssertEqual(state.queue.first?.id, firstId, "Oldest request must not be evicted when under cap")
        XCTAssertEqual(state.queue.last?.id, newRequest.id)
    }

    /// Builds a token request with a specific id and enqueue timestamp for eviction tests.
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

    func testEnqueueRequestEvictsRequestWithOldestEnqueuedAtRegardlessOfPosition() {
        // Arrange: a full queue whose oldest request sits in the middle, not at the front.
        let maxSize = StateManagementConstants.maxQueueSize
        let base = Date(timeIntervalSince1970: 1_000_000)
        var requests = (0..<maxSize).map { index in
            makeTokenRequest(id: "req-\(index)", enqueuedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        // Make an interior element the oldest (older than the front request).
        let oldestId = "oldest"
        requests[100] = makeTokenRequest(id: oldestId, enqueuedAt: base.addingTimeInterval(-1000))

        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // Act: enqueue a brand-new (newest) request at capacity.
        let newRequest = makeTokenRequest(id: "new", enqueuedAt: base.addingTimeInterval(10_000))
        state.enqueueRequest(request: newRequest)

        // Assert: the interior oldest-by-timestamp request is the one evicted, not the front.
        XCTAssertEqual(state.queue.count, maxSize)
        XCTAssertFalse(
            state.queue.contains { $0.id == oldestId },
            "Request with the oldest enqueuedAt must be evicted regardless of position"
        )
        XCTAssertTrue(
            state.queue.contains { $0.id == "req-0" },
            "The front request is newer than the interior oldest, so it must survive"
        )
        XCTAssertEqual(state.queue.last?.id, "new", "New request must be appended at the tail")
    }

    func testEnqueueRequestDrainsQueueAlreadyOverCapacity() {
        // Arrange: a queue that is already ABOVE capacity — reachable via init-time queue
        // merging or in-flight requests reinserted at the front. A single eviction per enqueue
        // would never restore the bound; eviction must drain all the way down in one call.
        let maxSize = StateManagementConstants.maxQueueSize
        let overCapacity = maxSize + 25
        let base = Date(timeIntervalSince1970: 1_000_000)
        let requests = (0..<overCapacity).map { index in
            makeTokenRequest(id: "req-\(index)", enqueuedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // Act: one enqueue.
        let newRequest = makeTokenRequest(id: "new", enqueuedAt: base.addingTimeInterval(999_999))
        state.enqueueRequest(request: newRequest)

        // Assert the exact resulting contents: the oldest 26 (req-0…req-25) are evicted, the
        // rest survive in their original order, and the newcomer is at the tail. Comparing the
        // full id list proves oldest-first draining — a spot-check could pass while removing
        // arbitrary entries.
        let expectedIds = (26..<overCapacity).map { "req-\($0)" } + ["new"]
        XCTAssertEqual(
            state.queue.map(\.id),
            expectedIds,
            "One enqueue must drain an over-capacity queue to the cap, evicting the oldest first"
        )
        XCTAssertEqual(state.queue.count, maxSize)
    }

    func testEnqueuePriorityRequestInsertsAtFrontAndStaysBounded() {
        // Arrange: a full queue of older requests.
        let maxSize = StateManagementConstants.maxQueueSize
        let base = Date(timeIntervalSince1970: 1_000_000)
        let requests = (0..<maxSize).map { index in
            makeTokenRequest(id: "old-\(index)", enqueuedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // Act: insert a prioritized (newest) event via the priority path.
        let priority = makeTokenRequest(id: "priority", enqueuedAt: base.addingTimeInterval(10_000))
        state.enqueuePriorityRequest(request: priority)

        // Assert: cap is held, priority event is at the front and survived, oldest was evicted.
        XCTAssertEqual(
            state.queue.count, maxSize, "Priority path must keep the queue bounded at maxQueueSize"
        )
        XCTAssertEqual(state.queue.first?.id, "priority", "Prioritized request must be inserted at the front")
        XCTAssertTrue(state.queue.contains { $0.id == "priority" }, "Prioritized request must not be evicted")
        XCTAssertFalse(
            state.queue.contains { $0.id == "old-0" }, "Oldest request must be evicted to make room"
        )
    }

    func testFreshPriorityRequestSurvivesSubsequentNormalOverflow() {
        // Arrange: a queue one below capacity, all older than the priority event.
        let maxSize = StateManagementConstants.maxQueueSize
        let base = Date(timeIntervalSince1970: 1_000_000)
        let requests = (0..<(maxSize - 1)).map { index in
            makeTokenRequest(id: "old-\(index)", enqueuedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // A prioritized event is inserted at the front with the newest timestamp, filling the queue.
        state.enqueuePriorityRequest(
            request: makeTokenRequest(id: "priority", enqueuedAt: base.addingTimeInterval(10_000))
        )
        XCTAssertEqual(state.queue.count, maxSize)

        // Act: a normal enqueue now overflows the queue.
        state.enqueueRequest(
            request: makeTokenRequest(id: "new", enqueuedAt: base.addingTimeInterval(20_000))
        )

        // Assert: the freshly front-inserted priority event is protected; an older request is evicted.
        XCTAssertEqual(state.queue.count, maxSize)
        XCTAssertTrue(
            state.queue.contains { $0.id == "priority" },
            "A freshly front-inserted priority event must not be evicted by a normal overflow"
        )
        XCTAssertFalse(state.queue.contains { $0.id == "old-0" }, "The oldest request must be evicted")
        XCTAssertEqual(state.queue.last?.id, "new", "New normal request must be appended at the tail")
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

    func testLegacyRequestsWithoutEnqueuedAtAreEvictedFirstAfterUpgrade() throws {
        // Build a legacy request via JSON round-trip with `enqueuedAt` stripped, so it genuinely
        // decodes to distantPast the same way a persisted pre-upgrade request would.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let seedData = try KlaviyoEnvironment.encoder.encode(
            makeTokenRequest(id: "legacy", enqueuedAt: Date(timeIntervalSince1970: 5000))
        )
        var seedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: seedData) as? [String: Any])
        seedJSON.removeValue(forKey: "enqueuedAt")
        let legacyRequest = try decoder.decode(
            KlaviyoRequest.self,
            from: JSONSerialization.data(withJSONObject: seedJSON)
        )
        XCTAssertEqual(
            legacyRequest.enqueuedAt, .distantPast, "Precondition: legacy request decodes to distantPast"
        )

        // Fill the queue to capacity with newer, real-timestamped requests, placing the legacy
        // request at an interior position (not the front) to prove eviction keys on timestamp.
        let maxSize = StateManagementConstants.maxQueueSize
        let base = Date(timeIntervalSince1970: 1_000_000)
        var requests = (0..<(maxSize - 1)).map { index in
            makeTokenRequest(id: "new-\(index)", enqueuedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        requests.insert(legacyRequest, at: 50)
        XCTAssertEqual(requests.count, maxSize)

        var state = KlaviyoState(apiKey: TEST_API_KEY, anonymousId: "anon", queue: requests)

        // Act: a normal enqueue overflows the queue.
        state.enqueueRequest(
            request: makeTokenRequest(id: "newest", enqueuedAt: base.addingTimeInterval(99_999))
        )

        // Assert: the legacy (distantPast) request is evicted before any newer request.
        XCTAssertEqual(state.queue.count, maxSize)
        XCTAssertFalse(
            state.queue.contains { $0.id == "legacy" },
            "Legacy request (distantPast) must be evicted before newer real-timestamped requests"
        )
        XCTAssertTrue(state.queue.contains { $0.id == "new-0" }, "Real-timestamped requests must survive")
        XCTAssertEqual(state.queue.last?.id, "newest")
    }

    // MARK: - ProfileData migration

    func testDecodesLegacyFlatIdentityJSON() throws {
        let jsonString = """
        {
          "apiKey": "company-id",
          "email": "a@b.com",
          "phoneNumber": "+15555555555",
          "externalId": "ext-1",
          "anonymousId": "anon-1",
          "queue": []
        }
        """
        let json = Data(jsonString.utf8)

        let state = try JSONDecoder().decode(KlaviyoState.self, from: json)

        XCTAssertEqual(state.identity.email, "a@b.com")
        XCTAssertEqual(state.identity.phoneNumber, "+15555555555")
        XCTAssertEqual(state.identity.externalId, "ext-1")
        XCTAssertEqual(state.identity.anonymousId, "anon-1")
        XCTAssertEqual(state.apiKey, "company-id")
    }

    func testDecodesNewNestedIdentityJSON() throws {
        let jsonString = """
        {
          "apiKey": "company-id",
          "identity": {
            "email": "a@b.com",
            "phoneNumber": "+15555555555",
            "externalId": "ext-1",
            "anonymousId": "anon-1"
          },
          "queue": []
        }
        """
        let json = Data(jsonString.utf8)

        let state = try JSONDecoder().decode(KlaviyoState.self, from: json)

        XCTAssertEqual(state.identity.email, "a@b.com")
        XCTAssertEqual(state.identity.phoneNumber, "+15555555555")
        XCTAssertEqual(state.identity.externalId, "ext-1")
        XCTAssertEqual(state.identity.anonymousId, "anon-1")
    }

    func testEncodesIdentityAsNestedObject() throws {
        let state = KlaviyoState(
            apiKey: "company-id",
            email: "a@b.com",
            anonymousId: "anon-1",
            queue: []
        )

        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["email"], "identity fields must not be encoded at the top level")
        XCTAssertNil(object["phoneNumber"], "identity fields must not be encoded at the top level")
        XCTAssertNil(object["externalId"], "identity fields must not be encoded at the top level")
        XCTAssertNil(object["anonymousId"], "identity fields must not be encoded at the top level")
        let identity = try XCTUnwrap(object["identity"] as? [String: Any])
        XCTAssertEqual(identity["email"] as? String, "a@b.com")
        XCTAssertEqual(identity["anonymousId"] as? String, "anon-1")
    }
}
