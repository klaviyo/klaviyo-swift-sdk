//
//  EncodableTests.swift
//
//
//  Created by Ajay Subramanya on 8/15/24.
//

import Foundation

@testable import KlaviyoCore
@testable import KlaviyoSwift
import SnapshotTesting
import XCTest

final class EncodableTests: XCTestCase {
    let testEncoder = KlaviyoEnvironment.encoder

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testKlaviyoState() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo")
        )
        let request = KlaviyoRequest(id: KlaviyoEnvironment.test().uuid().uuidString, apiKey: "foo", endpoint: .registerPushToken(tokenPayload))
        let klaviyoState = KlaviyoState(
            email: "foo",
            anonymousId: "foo",
            phoneNumber: "foo",
            pushTokenData: KlaviyoState.PushTokenData(
                pushToken: "foo",
                pushEnablement: .authorized,
                pushBackground: .available,
                deviceData: .init(context: KlaviyoEnvironment.test().appContextInfo())
            ),
            queue: [request],
            requestsInFlight: [request]
        )
        assertSnapshot(matching: klaviyoState, as: .json(KlaviyoEnvironment.encoder))
    }
}
