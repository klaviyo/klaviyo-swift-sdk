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

@MainActor
final class EncodableTests: XCTestCase {
    let testEncoder = KlaviyoEnvironment.encoder

    @MainActor
    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    func testKlaviyoState() async throws {
        let tokenPayload = PushTokenPayload(
            pushToken: "foo",
            enablement: "AUTHORIZED",
            background: "AVAILABLE",
            profile: ProfilePayload(email: "foo", phoneNumber: "foo", anonymousId: "foo"),
            appContextInfo: .test)
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .registerPushToken(tokenPayload), uuid: environment.uuid().uuidString)
        let klaviyoState = KlaviyoState(
            email: "foo",
            anonymousId: "foo",
            phoneNumber: "foo",
            pushTokenData: KlaviyoState.PushTokenData(
                pushToken: "foo",
                pushEnablement: .authorized,
                pushBackground: .available,
                deviceData: .init(context: AppContextInfo.test)),
            queue: [request],
            requestsInFlight: [request])
        assertSnapshot(matching: klaviyoState, as: .json(KlaviyoEnvironment.encoder))
    }
}
