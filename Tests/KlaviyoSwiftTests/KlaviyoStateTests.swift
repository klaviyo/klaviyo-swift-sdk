//
//  KlaviyoStateTests.swift
//
//
//  Created by Noah Durell on 12/1/22.
//

@testable import KlaviyoSwift
import AnyCodable
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
            try! JSONEncoder().encode(KlaviyoState(apiKey: "foo", anonymousId: environment.uuid().uuidString, queue: [], requestsInFlight: []))
        }
        environment.decoder = DataDecoder(jsonDecoder: KlaviyoEnvironment.decoder)

        let state = loadKlaviyoStateFromDisk(apiKey: "foo")
        assertSnapshot(matching: state, as: .dump)
    }

    func testFullKlaviyoStateEncodingDecodingIsEqual() throws {
        let event = Event.test
        let createEventPayload = CreateEventPayload(data: .init(event: event))
        let eventRequest = KlaviyoRequest(apiKey: "foo", endpoint: .createEvent(createEventPayload))
        let profile = Profile.test
        let data = CreateProfilePayload.Profile(profile: profile, anonymousId: "foo")
        let payload = CreateProfilePayload(data: data)
        let profileRequest = KlaviyoRequest(apiKey: "foo", endpoint: .createProfile(payload))
        let tokenPayload = KlaviyoRequest.KlaviyoEndpoint.PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: .init(email: "foo", phoneNumber: "foo"),
            anonymousId: "foo")
        let tokenRequest = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        let state = KlaviyoState(apiKey: "key", queue: [tokenRequest, profileRequest, eventRequest])
        let encodedState = try environment.encodeJSON(AnyEncodable(state))
        let decodedState: KlaviyoState = try environment.decoder.decode(encodedState)
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
}
