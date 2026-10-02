//
//  AuthTokenResetTests.swift
//  klaviyo-swift-sdk
//
//  Covers which reducer actions drop the auth token cached for an outgoing profile.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

@MainActor
final class AuthTokenResetTests: XCTestCase {
    private let identifiedState = KlaviyoState(
        apiKey: TEST_API_KEY,
        email: "old@example.com",
        anonymousId: "anon-old",
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized
    )

    private let anonymousState = KlaviyoState(
        apiKey: TEST_API_KEY,
        anonymousId: "anon-old",
        queue: [],
        requestsInFlight: [],
        initalizationState: .initialized
    )

    private var clears: ClearRecorder!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        let clears = ClearRecorder()
        self.clears = clears
        klaviyoSwiftEnvironment.clearAuthTokenState = { clears.count += 1 }
    }

    override func tearDown() async throws {
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        clears = nil
        try await super.tearDown()
    }

    // MARK: - Replacements

    func testResetProfileOfIdentifiedProfileClearsAuthToken() async {
        await assertAuthTokenClears(1, from: identifiedState, after: .resetProfile)
    }

    func testSetProfileWithNewEmailClearsAuthToken() async {
        await assertAuthTokenClears(
            1,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "new@example.com"))
        )
    }

    func testSetEmailOnAnonymousProfileClearsAuthToken() async {
        await assertAuthTokenClears(1, from: anonymousState, after: .setEmail("new@example.com"))
    }

    func testSetDifferentEmailClearsAuthToken() async {
        await assertAuthTokenClears(1, from: identifiedState, after: .setEmail("new@example.com"))
    }

    func testSetConflictingExternalIdClearsAuthToken() async {
        var state = identifiedState
        state.externalId = "external-a"
        await assertAuthTokenClears(1, from: state, after: .setExternalId("external-b"))
    }

    // MARK: - Compatible or unchanged

    func testResetProfileOfAnonymousProfileKeepsAuthToken() async {
        await assertAuthTokenClears(0, from: anonymousState, after: .resetProfile)
    }

    func testSetProfileAddingPhoneNumberToSameEmailKeepsAuthToken() async {
        await assertAuthTokenClears(
            0,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "old@example.com", phoneNumber: "+15555550100"))
        )
    }

    func testSetProfileWithSameIdentifiersKeepsAuthToken() async {
        await assertAuthTokenClears(
            0,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "old@example.com"))
        )
    }

    func testSetPhoneNumberOnIdentifiedProfileKeepsAuthToken() async {
        await assertAuthTokenClears(0, from: identifiedState, after: .setPhoneNumber("+15555550100"))
    }

    func testCompleteInitializationKeepsAuthToken() async {
        var uninitialized = KlaviyoState(queue: [], requestsInFlight: [])
        uninitialized.initalizationState = .initializing
        await assertAuthTokenClears(0, from: uninitialized, after: .completeInitialization(identifiedState))
    }

    // MARK: - Helpers

    private func assertAuthTokenClears(
        _ expected: Int,
        from initialState: KlaviyoState,
        after action: KlaviyoAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        _ = await store.send(action)
        XCTAssertEqual(clears.count, expected, "auth token clears", file: file, line: line)
    }
}

private final class ClearRecorder {
    var count = 0
}
