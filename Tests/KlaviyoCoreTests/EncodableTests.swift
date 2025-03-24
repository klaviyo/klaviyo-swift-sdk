//
//  EncodableTests.swift
//
//
//  Created by Noah Durell on 11/14/22.
//

@testable import KlaviyoCore
import SnapshotTesting
import XCTest

@MainActor
final class EncodableTests: XCTestCase {
    let testEncoder = KlaviyoEnvironment.encoder

    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testProfilePayload() throws {
        let payload = CreateProfilePayload(data: .test)
        assertSnapshot(of: payload, as: .json(KlaviyoEnvironment.encoder))
    }

    @MainActor
    func testEventPayload() async throws {
        let payloadData = CreateEventPayload.Event(name: "test", properties: SAMPLE_PROPERTIES, anonymousId: "anon-id", pushToken: "", appContextInfo: AppContextInfo.test)
        let createEventPayload = CreateEventPayload(data: payloadData)
        assertSnapshot(of: createEventPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testTokenPayload() async throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"), appContextInfo: environment.appContextInfo())
        assertSnapshot(of: tokenPayload, as: .json(KlaviyoEnvironment.encoder))
    }

    func testUnregisterTokenPayload() throws {
        let tokenPayload = UnregisterPushTokenPayload(
            pushToken: "foo",
            email: "foo",
            phoneNumber: "foo",
            anonymousId: "foo")
        assertSnapshot(of: tokenPayload, as: .json)
    }

    func testKlaviyoRequest() async throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"),
            appContextInfo: environment.appContextInfo()) 
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload), uuid: environment.uuid().uuidString)
        assertSnapshot(of: request, as: .json)
    }
}
