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
        let payload = CreateProfilePayload(data: profile.toAPIModel(anonymousId: "foo"))

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
}
