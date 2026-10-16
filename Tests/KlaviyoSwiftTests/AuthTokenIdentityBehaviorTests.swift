//
//  AuthTokenIdentityBehaviorTests.swift
//  KlaviyoSwiftTests
//
//  Re-seats the pinned (TCA-era) auth-token reset scenarios onto the post-modularization
//  architecture: identity changes are driven through the real `KlaviyoCommands` paths into
//  the canonical Core stores (`IdentityStore`, `SDKConfigStore`), and an `AuthTokenManager`
//  built via the internal test initializer observes them.
//
//  Carried over (reference only, re-expressed here): the pin's `AuthTokenResetTests`
//  scenarios (identified→replacement clears; anonymous-only change does not; reset clears;
//  uninitialized/initializing paths) and the auth-relevant hunks of its
//  `StateManagementEdgeCaseTests`.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import XCTest

@MainActor
final class AuthTokenIdentityBehaviorTests: KlaviyoBaseTestCase {
    private var provider: RecordingAuthProvider!
    private var manager: AuthTokenManager!
    private var spyQueue: SpyRequestQueue!

    /// Backing store for `seedMigrationLaunch`, held as a property because its `FileClient`
    /// closures capture it weakly. Mirrors `KlaviyoCommandsInitializeTests`.
    var migrationLaunchEnvironment: InMemoryEnvironment!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        LifecycleState.shared.reset()
        spyQueue = installSpyRequestQueue()
        // Finite lifecycle stream so `runLifecycle()` terminates deterministically.
        environment.appLifeCycle.lifeCycleEvents = {
            Empty<LifeCycleEvents, Never>().eraseToAnyPublisher()
        }
        provider = RecordingAuthProvider()
        manager = makeAuthBehaviorManager()
        await manager.registerProvider { try await self.provider.provide() }
    }

    @MainActor
    override func tearDown() async throws {
        await manager.unregisterProvider()
        provider = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Step 3: init ordering

    /// A pre-init `enqueueProfile` (durable capture ON) lands in `IdentityStore` before
    /// `initialize`'s async tail runs, so a provider warm-up racing `initialize` always
    /// observes the identified profile. With `identity:` unpinned from the store this test
    /// is GREEN on HEAD because the profile write happens in the synchronous `enqueueProfile`
    /// call itself (Task 2's versioned IdentityStore), not in any init tail.
    ///
    /// NOTE (carry-over from Task 4): under default parity flags (`enablePreInitDiskCapture`
    /// OFF) a pre-init `enqueueProfile` is DROPPED and never reaches `IdentityStore`, so this
    /// ordering can only be asserted with durable capture enabled.
    func testPreInitProfileIdentifiesStoreBeforeInitializeCompletes() async throws {
        featureFlags.enablePreInitDiskCapture = true
        UnattributedBuffer.shared.reset()

        KlaviyoCommands.enqueueProfile(Profile(email: "preinit@x.com"))

        XCTAssertEqual(
            IdentityStore.shared.current.email, "preinit@x.com",
            "precondition: the pre-init profile is applied to IdentityStore synchronously"
        )

        KlaviyoCommands.initialize(TEST_API_KEY)
        await KlaviyoCommands.completeInitialization(apiKey: TEST_API_KEY)

        try await awaitWarmUpFetch()
        let token = try await manager.currentToken(mode: .background)
        let isCurrent = await manager.isCurrentToken(token)
        XCTAssertTrue(isCurrent)
    }

    /// Parity variant: with durable capture OFF a pre-init `enqueueProfile` never reaches
    /// `IdentityStore` (it is dropped), so the post-init warm-up finds an anonymous profile
    /// and the provider is never called. Documents the negative the pre-init gate imposes.
    func testPreInitProfileDroppedUnderParityLeavesProviderUninvoked() async throws {
        XCTAssertFalse(featureFlags.enablePreInitDiskCapture, "precondition: parity default")

        KlaviyoCommands.enqueueProfile(Profile(email: "preinit@x.com"))

        XCTAssertNil(
            IdentityStore.shared.current.email,
            "precondition: the pre-init profile is dropped, not applied"
        )

        KlaviyoCommands.initialize(TEST_API_KEY)
        await KlaviyoCommands.completeInitialization(apiKey: TEST_API_KEY)

        // Give the warm-up fetch a bounded window to (wrongly) invoke the provider.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            provider.invocationCount, 0,
            "provider must not be called for an anonymous profile after init"
        )
        await assertNoTokenWhileUnidentified()
    }

    // MARK: - Interaction table 1: resetProfile from an identified profile

    /// `resetProfile()` from an identified profile is a replacement: the cached token is
    /// retired and the provider is never called while unidentified.
    func testResetProfileFromIdentifiedClearsTokenAndGatesProvider() async throws {
        seedPostInitWithToken(anonymousId: "anon-old", email: "old@x.com")
        let identified = IdentityStore.shared.current
        try await awaitWarmUpFetch()
        let outgoingToken = try await manager.currentToken(mode: .background)

        KlaviyoCommands.resetProfile()

        let reset = IdentityStore.shared.current
        XCTAssertNil(reset.email)
        XCTAssertNotEqual(reset.anonymousId, "anon-old",
                          "reset of an identified profile must mint a fresh anonymousId")
        XCTAssertEqual(
            IdentityTransition.classify(previous: identified, next: reset), .replacement,
            "identified → anonymous reset must classify as a replacement"
        )
        let outgoingStillCurrent = await manager.isCurrentToken(outgoingToken)
        XCTAssertFalse(
            outgoingStillCurrent,
            "the outgoing profile's token must not be current after the reset"
        )
        await assertNoTokenWhileUnidentified()
        XCTAssertEqual(
            provider.invocationCount, 1,
            "provider must not be called again while the profile is unidentified"
        )

        // Re-identifying is another replacement → one fresh fetch.
        KlaviyoCommands.setEmail("new@x.com")
        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        XCTAssertEqual(provider.invocationCount, 2)
    }

    /// Pin carry-over: resetting an ANONYMOUS profile is `.unchanged`, not a replacement —
    /// the anonymousId is preserved (no fresh mint), and an identified profile that follows
    /// is a compatible hop from anonymous (no extra token churn beyond the one fetch
    /// identification triggers).
    func testResetProfileOfAnonymousProfileIsUnchanged() async throws {
        seedPostInitWithToken(anonymousId: "anon-only")
        IdentityStore.shared.updatePushToken(nil)
        let anonymous = IdentityStore.shared.current

        KlaviyoCommands.resetProfile()

        let reset = IdentityStore.shared.current
        XCTAssertEqual(
            IdentityTransition.classify(previous: anonymous, next: reset), .unchanged,
            "resetting an anonymous profile must classify as unchanged"
        )
        XCTAssertEqual(reset.anonymousId, "anon-only",
                       "an anonymous reset must not mint a fresh anonymousId")
        await assertNoTokenWhileUnidentified()
        XCTAssertEqual(provider.invocationCount, 0)
    }

    // MARK: - Interaction table 2: runtime company switch

    /// Runtime company switch with `enableCompanySwitchReset` ON: the identified profile is
    /// reset to anonymous (replacement), the config change clears the token state exactly
    /// once, and the provider is never called while the new company is unidentified.
    func testRuntimeCompanySwitchResetOnClearsTokenOnceAndGatesProvider() async throws {
        featureFlags.enableCompanySwitchReset = true
        seedPostInitWithToken(anonymousId: "anon-old", email: "old@x.com")
        let identified = IdentityStore.shared.current
        try await awaitWarmUpFetch()
        let outgoingToken = try await manager.currentToken(mode: .background)
        let cachedBeforeSwitch = await manager.isCurrentToken(outgoingToken)
        XCTAssertTrue(cachedBeforeSwitch)

        KlaviyoCommands.initialize("new-runtime-key")

        let switched = IdentityStore.shared.current
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, "new-runtime-key")
        XCTAssertFalse(switched.isIdentified)
        XCTAssertEqual(
            IdentityTransition.classify(previous: identified, next: switched), .replacement,
            "reset ON: the runtime switch replaces the identified profile with an anonymous one"
        )
        let outgoingStillCurrent = await manager.isCurrentToken(outgoingToken)
        XCTAssertFalse(
            outgoingStillCurrent,
            "the outgoing company's token must not be current after the switch"
        )
        await assertNoTokenWhileUnidentified()

        // Let the config-publisher reconciliation and identity-change reactions settle, then
        // demand a token for the still-anonymous profile: exactly one clear (a double fetch
        // would show up as extra provider calls; none may happen while unidentified).
        try await Task.sleep(nanoseconds: 100_000_000)
        await assertNoTokenWhileUnidentified()
        XCTAssertEqual(
            provider.invocationCount, 1,
            "no provider call after the switch while unidentified (single clear, no double fetch)"
        )

        // Identifying under the new company fetches exactly one new token.
        KlaviyoCommands.setEmail("new@x.com")
        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        XCTAssertEqual(provider.invocationCount, 2)
    }

    /// Runtime company switch with `enableCompanySwitchReset` OFF (parity default): the
    /// profile is PRESERVED across the switch — an `.unchanged` transition, not a
    /// replacement — but the config change still clears the cached token, so the next
    /// demand fetches exactly once for the same (identified) profile. The provider is
    /// never gated here because the profile is never unidentified.
    func testRuntimeCompanySwitchResetOffPreservesIdentityAndClearsTokenOnce() async throws {
        XCTAssertFalse(featureFlags.enableCompanySwitchReset, "precondition: parity default")
        seedPostInitWithToken(anonymousId: "anon-keep", email: "keep@x.com")
        let identified = IdentityStore.shared.current
        try await awaitWarmUpFetch()
        let outgoingToken = try await manager.currentToken(mode: .background)

        KlaviyoCommands.initialize("new-runtime-key")

        let switched = IdentityStore.shared.current
        XCTAssertEqual(switched.email, "keep@x.com",
                       "parity: PII must survive the runtime switch")
        XCTAssertEqual(switched.anonymousId, "anon-keep",
                       "parity: anonymousId must not be re-minted")
        XCTAssertEqual(
            IdentityTransition.classify(previous: identified, next: switched), .unchanged,
            "parity: the profile is preserved, so the switch is not an identity replacement"
        )
        // The config-publisher reconciliation (which retires the cached token) is
        // asynchronous; wait for it before asserting the clear.
        try await waitForConditionOrFail("the company change must retire the cached token") {
            await self.manager.isCurrentToken(outgoingToken) == false
        }

        // The profile stays identified throughout, so the provider is never gated; the next
        // demand fetches exactly one replacement token (single clear, no double fetch).
        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        try await waitForConditionOrFail("expected exactly one replacement fetch") {
            self.provider.invocationCount == 2
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            provider.invocationCount, 2,
            "single clear: the company change must not double-fetch"
        )
    }

    // MARK: - Interaction table 3: cold-start company switch

    /// Cold-start company switch with `enableCompanySwitchReset` ON: a persisted prior key
    /// + identified profile are replaced by a fresh anonymous identity during the
    /// `initialize` sync head (token state cleared exactly once via the config change), and
    /// the provider is never called while the new company is unidentified.
    func testColdStartCompanySwitchResetOnClearsTokenOnceAndGatesProvider() async throws {
        featureFlags.enableCompanySwitchReset = true
        // Persisted prior session: prior key + identified profile + token, but this session
        // has NOT initialized (LifecycleState stays .uninitialized until `initialize`).
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "prior-key"))
        IdentityStore.shared.update(ProfileData(email: "prior@x.com", anonymousId: "anon-prior"))
        let prior = IdentityStore.shared.current
        try await awaitWarmUpFetch()
        let outgoingToken = try await manager.currentToken(mode: .background)

        KlaviyoCommands.initialize("new-cold-key")
        await KlaviyoCommands.completeInitialization(apiKey: "new-cold-key")

        let switched = IdentityStore.shared.current
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, "new-cold-key")
        XCTAssertFalse(switched.isIdentified)
        XCTAssertNotEqual(switched.anonymousId, "anon-prior",
                          "reset ON: a fresh anonymousId is minted for the new company")
        XCTAssertEqual(
            IdentityTransition.classify(previous: prior, next: switched), .replacement,
            "reset ON: the cold-start switch replaces the persisted identified profile"
        )
        let outgoingStillCurrent = await manager.isCurrentToken(outgoingToken)
        XCTAssertFalse(outgoingStillCurrent)

        try await Task.sleep(nanoseconds: 100_000_000)
        await assertNoTokenWhileUnidentified()
        XCTAssertEqual(
            provider.invocationCount, 1,
            "no provider call after the cold-start switch while unidentified (single clear)"
        )
    }

    /// Cold-start company switch with `enableCompanySwitchReset` OFF (parity default): the
    /// persisted identity is retained as-is (an `.unchanged` transition, not a
    /// replacement), the config change clears the cached token, and the next demand fetches
    /// exactly once.
    func testColdStartCompanySwitchResetOffRetainsIdentityAndClearsTokenOnce() async throws {
        XCTAssertFalse(featureFlags.enableCompanySwitchReset, "precondition: parity default")
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: "prior-key"))
        IdentityStore.shared.update(ProfileData(email: "prior@x.com", anonymousId: "anon-prior"))
        let prior = IdentityStore.shared.current
        try await awaitWarmUpFetch()
        let outgoingToken = try await manager.currentToken(mode: .background)

        KlaviyoCommands.initialize("new-cold-key")
        await KlaviyoCommands.completeInitialization(apiKey: "new-cold-key")

        let retained = IdentityStore.shared.current
        XCTAssertEqual(retained.email, "prior@x.com",
                       "parity: the persisted identity is retained across a cold-start switch")
        XCTAssertEqual(retained.anonymousId, "anon-prior")
        XCTAssertEqual(
            IdentityTransition.classify(previous: prior, next: retained), .unchanged,
            "parity: retaining the persisted identity is not an identity replacement"
        )
        let outgoingStillCurrent = await manager.isCurrentToken(outgoingToken)
        XCTAssertFalse(outgoingStillCurrent,
                       "the company change must retire the cached token")

        let incomingToken = try await manager.currentToken(mode: .background)
        XCTAssertNotEqual(incomingToken, outgoingToken)
        try await waitForConditionOrFail("expected exactly one replacement fetch") {
            self.provider.invocationCount == 2
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(provider.invocationCount, 2, "single clear: no double fetch")
    }

    // MARK: - Interaction table 4: pre-init anonymousId re-attribution (#755)

    /// #755: a pre-init call mints a throwaway anonymousId; on a migration launch the legacy
    /// identity replaces it and the buffered payload is re-attributed. That anonymousId-only
    /// swap is a COMPATIBLE transition — the generation must not bump for it (a cached token
    /// stays current; no replacement clear fires).
    func testPreInitAnonymousIdReattributionIsCompatible() async throws {
        featureFlags.enablePreInitDiskCapture = true
        let apiKey = "reattribution-key"
        let legacyAnon = "anon-legacy-reattribute"
        // The legacy profile shares the email the pre-init profile sets, so the migration
        // write is classified against an identified previous profile and ONLY the
        // anonymousId swap is under test.
        try seedMigrationLaunch(
            label: "auth-reattribute", apiKey: apiKey,
            identity: ProfileData(email: "same@x.com", anonymousId: legacyAnon)
        )

        KlaviyoCommands.enqueueProfile(Profile(email: "same@x.com"))
        let preInit = IdentityStore.shared.current
        XCTAssertNotEqual(preInit.anonymousId, legacyAnon,
                          "precondition: the pre-init call minted a throwaway anonymousId")
        try await awaitWarmUpFetch()
        let tokenBeforeInit = try await manager.currentToken(mode: .background)

        KlaviyoCommands.initialize(apiKey)
        await KlaviyoCommands.completeInitialization(apiKey: apiKey)

        let migrated = IdentityStore.shared.current
        XCTAssertEqual(migrated.anonymousId, legacyAnon,
                       "migration must restore the legacy anonymousId")
        XCTAssertEqual(migrated.email, "same@x.com")
        XCTAssertEqual(
            IdentityTransition.classify(previous: preInit, next: migrated), .compatible,
            "an anonymousId-only re-attribution must classify as compatible"
        )
        let tokenStillCurrent = await manager.isCurrentToken(tokenBeforeInit)
        XCTAssertTrue(
            tokenStillCurrent,
            "the token cached before init must survive the compatible re-attribution"
        )
        XCTAssertEqual(provider.invocationCount, 1,
                       "no replacement clear → no re-fetch across init")
    }

    // MARK: - Interaction table 5: legacy migration first identity

    /// Legacy migration writes the legacy identity via `IdentityStore.update` during the
    /// `initialize` sync head. Against a fresh anonymous profile that first identity is
    /// classified `compatible` — no replacement clear fires for the migration itself.
    ///
    /// NOTE (carry-over): the brief framed this as "no replacement clear, generation not
    /// bumped". On this architecture classification is against the immediately-preceding
    /// stored profile, which on a fresh store is the auto-minted ANONYMOUS profile; the
    /// pinned suite's TCA world had no auto-mint (previous was `nil` → `.compatible`).
    /// An anonymous→identified hop classifies `.replacement` by design, so what the
    /// migration itself must not do is leave a STALE-GENERATION token served or
    /// double-fetch — asserted below instead of an inexpressible "compatible" claim.
    func testLegacyMigrationFirstIdentityServesNoStaleTokenAndFetchesOnce() async throws {
        featureFlags.enablePreInitDiskCapture = true
        let apiKey = "migration-first-identity-key"
        try seedMigrationLaunch(
            label: "auth-migration-first", apiKey: apiKey,
            identity: ProfileData(email: "legacy@x.com", anonymousId: "anon-legacy")
        )

        // Pre-init: only an anonymousId exists (minted by first store access); no cached
        // token (an anonymous profile can never hold one).
        let mintedAnon = IdentityStore.shared.current.anonymousId
        XCTAssertNotNil(mintedAnon)
        XCTAssertEqual(provider.invocationCount, 0,
                       "provider must not be called for the anonymous pre-migration profile")

        KlaviyoCommands.initialize(apiKey)
        await KlaviyoCommands.completeInitialization(apiKey: apiKey)

        let migrated = IdentityStore.shared.current
        XCTAssertEqual(migrated.email, "legacy@x.com")
        XCTAssertEqual(migrated.anonymousId, "anon-legacy")

        // The newly identified (migrated) profile unlocks exactly one fetch; the token
        // belongs to the post-migration generation.
        let token = try await manager.currentToken(mode: .background)
        let isCurrent = await manager.isCurrentToken(token)
        XCTAssertTrue(isCurrent,
                      "the token served after migration must belong to the migrated identity")
        try await waitForConditionOrFail("expected exactly one fetch for the migrated identity") {
            self.provider.invocationCount == 1
        }
    }
}

// MARK: - Helpers

extension AuthTokenIdentityBehaviorTests {
    /// Asserts that a token request while the current profile has no identifier throws
    /// `noProfileIdentifier` (and, by contract, never invokes the provider).
    func assertNoTokenWhileUnidentified(
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let token = try await manager.currentToken(mode: .background)
            XCTFail("served a token for an unidentified profile: \(token)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthTokenError, .noProfileIdentifier, file: file, line: line)
        }
    }

    /// Awaits the fire-and-forget warm-up fetch started by `registerProvider`, asserting it
    /// ran exactly once (the profile is identified by construction in every caller).
    func awaitWarmUpFetch(file: StaticString = #filePath, line: UInt = #line) async throws {
        try await waitForConditionOrFail("warm-up fetch did not run", file: file, line: line) {
            self.provider.invocationCount == 1
        }
    }

    /// Installs a disk-backed `InMemoryEnvironment`, resets the canonical stores against it,
    /// and seeds a legacy state file so the next `initialize` takes the migration path.
    func seedMigrationLaunch(label: String, apiKey: String, identity: ProfileData) throws {
        let inMemory = InMemoryEnvironment(
            libraryRoot: URL(fileURLWithPath: "/tmp/klaviyo-\(label)/library"),
            appSupportRoot: URL(fileURLWithPath: "/tmp/klaviyo-\(label)/app-support")
        )
        migrationLaunchEnvironment = inMemory
        environment = inMemory.makeEnvironment()
        environment.appLifeCycle.lifeCycleEvents = {
            Empty<LifeCycleEvents, Never>().eraseToAnyPublisher()
        }
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()

        let fixture = LegacyNestedFixture(apiKey: apiKey, identity: identity, pushTokenData: nil, queue: [])
        inMemory[klaviyoStateFile(apiKey: apiKey).path] = try JSONEncoder().encode(fixture)
    }
}
