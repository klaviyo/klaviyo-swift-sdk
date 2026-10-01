//
//  CompanySwitchAuthTokenTests.swift
//  klaviyo-swift-sdk
//
//  Drives identity changes (a company switch via `initialize` with a new API key, and a
//  compatible change followed by a replacing one) through the KlaviyoSwift reducer, the
//  shared store mirror and IdentityStore into an AuthTokenManager.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import XCTest

@MainActor
final class CompanySwitchAuthTokenTests: XCTestCase {
    private let outgoingIdentity = ProfileData(email: "a@x.com", anonymousId: "anon-A")
    private var store: Store<KlaviyoState, KlaviyoAction>!
    private var provider: ScriptedTokenProvider!
    private var manager: AuthTokenManager!

    override func setUp() async throws {
        try await super.setUp()
        environment = KlaviyoEnvironment.test()
        SharedStoreMirror.reset()
        provider = ScriptedTokenProvider()
        manager = AuthTokenManager(
            lifeCycle: AppLifeCycleEvents(lifeCycleEvents: { Empty().eraseToAnyPublisher() }),
            currentDate: { Date() }
        )
    }

    override func tearDown() async throws {
        await manager.unregisterProvider()
        SharedStoreMirror.reset()
        store = nil
        manager = nil
        provider = nil
        try await super.tearDown()
    }

    func testCompanySwitchDoesNotServeOutgoingTokenAndGatesProviderUntilIdentified() async throws {
        let outgoingToken = try await startIdentifiedStore()
        XCTAssertEqual(IdentityStore.shared.current.email, outgoingIdentity.email)

        _ = store.send(.initialize("new-api-key"))

        let anonymous = IdentityStore.shared.current
        XCTAssertFalse(anonymous.isIdentified)
        XCTAssertEqual(IdentityTransition.classify(previous: outgoingIdentity, next: anonymous), .replacement)
        await assertNoTokenWhileAnonymous()
        let callsWhileAnonymous = await provider.invocationCount
        XCTAssertEqual(callsWhileAnonymous, 1)

        _ = store.send(.setEmail("a@x.com"))

        let identified = IdentityStore.shared.current
        XCTAssertEqual(identified.email, "a@x.com")
        XCTAssertEqual(IdentityTransition.classify(previous: anonymous, next: identified), .replacement)
        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        let callsAfterIdentified = await provider.invocationCount
        XCTAssertEqual(callsAfterIdentified, 2)
    }

    func testCompatibleChangeFollowedByReplacingChangeDropsOutgoingToken() async throws {
        let outgoingToken = try await startIdentifiedStore()

        _ = store.send(.setPhoneNumber("+15551234567"))
        _ = store.send(.setPhoneNumber("+15557654321"))

        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        let calls = await provider.invocationCount
        XCTAssertEqual(calls, 2)
    }

    func testScalarReplacementKeepsAnonymousIdButDropsOutgoingToken() async throws {
        let outgoingToken = try await startIdentifiedStore(phoneNumber: "+15551234567")

        _ = store.send(.setEmail("b@x.com"))

        let incoming = IdentityStore.shared.current
        XCTAssertEqual(incoming.anonymousId, outgoingIdentity.anonymousId)
        XCTAssertEqual(incoming.phoneNumber, "+15551234567")
        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        let calls = await provider.invocationCount
        XCTAssertEqual(calls, 2)
    }

    func testScalarAndBulkReplacementsGiveTheSameTokenOutcome() async throws {
        for action in [
            KlaviyoAction.setEmail("b@x.com"),
            .enqueueProfile(Profile(email: "b@x.com"))
        ] {
            let outgoingToken = try await startIdentifiedStore()

            _ = store.send(action)

            let incomingToken = try await manager.currentToken(mode: .background)
            XCTAssertNotEqual(incomingToken, outgoingToken)
            let calls = await provider.invocationCount
            XCTAssertEqual(calls, 2)
            await tearDownRound()
        }
    }

    func testCompatibleBulkChangeThatResetsAnonymousIdKeepsTokenInOnePublish() async throws {
        let outgoingToken = try await startIdentifiedStore()
        let generation = manager.currentIdentityGeneration
        var emissions: [ProfileData] = []
        let observation = IdentityStore.shared.publisher.dropFirst().sink { emissions.append($0) }
        defer { observation.cancel() }

        _ = store.send(.enqueueProfile(Profile(email: "a@x.com", phoneNumber: "+15551234567")))

        let incoming = IdentityStore.shared.current
        XCTAssertNotEqual(incoming.anonymousId, outgoingIdentity.anonymousId)
        XCTAssertEqual(
            IdentityTransition.classify(previous: outgoingIdentity, next: incoming),
            .compatible
        )
        XCTAssertEqual(emissions, [incoming])
        XCTAssertEqual(manager.currentIdentityGeneration, generation)
        let token = try await manager.currentToken(mode: .background)
        XCTAssertEqual(token, outgoingToken)
        let calls = await provider.invocationCount
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Helpers

    private func tearDownRound() async {
        await manager.unregisterProvider()
        SharedStoreMirror.reset()
        provider = ScriptedTokenProvider()
    }

    /// Starts an initialized store for an identified profile, mirrors it into the shared
    /// Core stores and returns the token the manager caches for that profile.
    private func startIdentifiedStore(phoneNumber: String? = nil) async throws -> String {
        let state = KlaviyoState(
            apiKey: "abc123",
            email: outgoingIdentity.email,
            anonymousId: outgoingIdentity.anonymousId,
            phoneNumber: phoneNumber,
            queue: [],
            initalizationState: .initialized
        )
        let store = Store(initialState: state, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { store.state.eraseToAnyPublisher() }
        SharedStoreMirror.setup()
        self.store = store
        let provider = try XCTUnwrap(provider)
        await manager.registerProvider { try await provider.provide() }
        return try await manager.currentToken(mode: .background)
    }

    private func assertNoTokenWhileAnonymous(file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let token = try await manager.currentToken(mode: .background)
            XCTFail("served a token for an anonymous profile: \(token)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthTokenError, .noProfileIdentifier, file: file, line: line)
        }
    }
}
