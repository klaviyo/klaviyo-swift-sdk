//
//  AuthTokenResetTests.swift
//  klaviyo-swift-sdk
//
//  Covers how identity-changing reducer actions classify as identity transitions.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
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

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    override func tearDown() async throws {
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        try await super.tearDown()
    }

    // MARK: - Replacements

    func testResetProfileOfIdentifiedProfileIsReplacement() async {
        await assertTransition(.replacement, from: identifiedState, after: .resetProfile)
    }

    func testSetProfileWithNewEmailIsReplacement() async {
        await assertTransition(
            .replacement,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "new@example.com"))
        )
    }

    func testSetEmailOnAnonymousProfileIsReplacement() async {
        await assertTransition(.replacement, from: anonymousState, after: .setEmail("new@example.com"))
    }

    func testSetDifferentEmailIsReplacement() async {
        await assertTransition(.replacement, from: identifiedState, after: .setEmail("new@example.com"))
    }

    func testSetConflictingExternalIdIsReplacement() async {
        var state = identifiedState
        state.externalId = "external-a"
        await assertTransition(.replacement, from: state, after: .setExternalId("external-b"))
    }

    func testRejectedOnlyIdentifierIsReplacement() async {
        await assertTransition(
            .replacement,
            from: identifiedState,
            after: .resetStateAndDequeue(rejectedRequest, [.email])
        )
    }

    func testQueuedReplacementReplayedAtInitializationIsReplacement() async {
        var initializing = KlaviyoState(queue: [], requestsInFlight: [])
        initializing.initalizationState = .initializing
        initializing.pendingRequests = [.setEmail("new@example.com")]
        await assertTransition(
            .replacement,
            from: initializing,
            after: .completeInitialization(identifiedState),
            previous: identifiedState.identity
        )
    }

    // MARK: - Compatible or unchanged

    func testRejectedIdentifierLeavingSharedIdentifierIsNotReplacement() async {
        var state = identifiedState
        state.phoneNumber = "+15555550100"
        await assertTransition(.compatible, from: state, after: .resetStateAndDequeue(rejectedRequest, [.email]))
    }

    func testResetProfileOfAnonymousProfileIsNotReplacement() async {
        await assertTransition(.unchanged, from: anonymousState, after: .resetProfile)
    }

    func testSetProfileAddingPhoneNumberToSameEmailIsNotReplacement() async {
        await assertTransition(
            .compatible,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "old@example.com", phoneNumber: "+15555550100"))
        )
    }

    func testSetProfileWithSameIdentifiersIsNotReplacement() async {
        await assertTransition(
            .unchanged,
            from: identifiedState,
            after: .enqueueProfile(Profile(email: "old@example.com"))
        )
    }

    func testSetPhoneNumberOnIdentifiedProfileIsNotReplacement() async {
        await assertTransition(.compatible, from: identifiedState, after: .setPhoneNumber("+15555550100"))
    }

    func testCompleteInitializationIsNotReplacement() async {
        var uninitialized = KlaviyoState(queue: [], requestsInFlight: [])
        uninitialized.initalizationState = .initializing
        await assertTransition(
            .unchanged,
            from: uninitialized,
            after: .completeInitialization(identifiedState),
            previous: identifiedState.identity
        )
    }

    // MARK: - Cold launch

    func testQueuedIdentityIsTheFirstInitializedIdentityObserved() {
        SharedStoreMirror.reset()
        defer { SharedStoreMirror.reset() }
        var initializing = KlaviyoState(apiKey: TEST_API_KEY, queue: [], requestsInFlight: [])
        initializing.initalizationState = .initializing
        let store = Store(initialState: initializing, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { store.state.eraseToAnyPublisher() }
        SharedStoreMirror.setup()
        var observed: [ProfileData] = []
        let observation = IdentityStore.shared.publisher.sink { observed.append($0) }
        defer { observation.cancel() }

        _ = store.send(.enqueueProfile(Profile(email: "new@example.com")))
        _ = store.send(.completeInitialization(identifiedState))

        XCTAssertFalse(observed.contains { $0.email == identifiedState.email })
        XCTAssertEqual(IdentityStore.shared.current.email, "new@example.com")
    }

    // MARK: - Helpers

    private var rejectedRequest: KlaviyoRequest {
        KlaviyoRequest(endpoint: .createProfile(
            TEST_API_KEY,
            CreateProfilePayload(data: ProfilePayload(email: "old@example.com", anonymousId: "anon-old"))
        ))
    }

    private func assertTransition(
        _ expected: IdentityTransition,
        from initialState: KlaviyoState,
        after action: KlaviyoAction,
        previous: ProfileData? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        _ = await store.send(action)
        let transition = IdentityTransition.classify(
            previous: previous ?? initialState.identity,
            next: store.state.identity
        )
        XCTAssertEqual(transition, expected, "identity transition", file: file, line: line)
    }
}
