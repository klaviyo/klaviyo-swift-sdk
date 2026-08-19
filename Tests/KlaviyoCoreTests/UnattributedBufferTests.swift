//
//  UnattributedBufferTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

@testable import KlaviyoCore
import XCTest

final class UnattributedBufferTests: XCTestCase {
    private var fileIO: FileIODouble!

    override func setUp() {
        super.setUp()
        fileIO = FileIODouble()
        environment = fileIO.makeEnvironment()
    }

    override func tearDown() {
        environment = KlaviyoEnvironment.test()
        fileIO = nil
        super.tearDown()
    }

    func testPersistedBufferRoundTripsAllFourCases() throws {
        let eventPayload = CreateEventPayload(
            data: CreateEventPayload.Event(name: "Test", anonymousId: "anon-1"))
        let profilePayload = CreateProfilePayload(
            data: ProfilePayload(anonymousId: "anon-1"))
        let tokenPayload = PushTokenPayload(
            pushToken: "tok", enablement: "AUTHORIZED", background: "AVAILABLE",
            profile: ProfilePayload(anonymousId: "anon-1")
        )
        let original = PersistedUnattributedBuffer(
            version: PersistedUnattributedBuffer.currentVersion,
            requests: [
                .event(eventPayload, .high),
                .aggregateEvent(Data("agg".utf8)),
                .profile(profilePayload),
                .pushToken(tokenPayload)
            ]
        )

        let data = try environment.encodeJSON(original)
        let decoded: PersistedUnattributedBuffer = try environment.decoder.decode(data)

        XCTAssertEqual(decoded, original)
    }
}
