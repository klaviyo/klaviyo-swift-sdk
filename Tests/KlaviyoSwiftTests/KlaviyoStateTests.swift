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
