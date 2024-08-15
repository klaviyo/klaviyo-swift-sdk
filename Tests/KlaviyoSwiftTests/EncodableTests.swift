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

    func testKlaviyoState() throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"))
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload), uuid: environment.uuid().uuidString)
        let klaviyoState = KlaviyoState(
            email: "foo",
            anonymousId: "foo",
            phoneNumber: "foo",
            pushTokenData: .init(
                pushToken: "foo",
                pushEnablement: .authorized,
                pushBackground: .available,
                deviceData: .init(context: environment.appContextInfo())),
            queue: [request],
            requestsInFlight: [request])
        assertSnapshot(matching: klaviyoState, as: .json)
    }
}
