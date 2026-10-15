//
//  AuthTokenManagerStaleFetchTests.swift
//  KlaviyoCore
//
//  Covers what happens to a fetch still running for an earlier identity generation when a
//  fetch for the current generation replaces it.
//

@testable import KlaviyoCore
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct AuthTokenManagerStaleFetchTests {
    private let profileA = ProfileData(email: "a@example.com", anonymousId: "anon")
    private let profileB = ProfileData(email: "b@example.com", anonymousId: "anon-b")

    @Test
    func rejectedTokenRefreshCancelsTheStaleGenerationFetchItReplaces() async throws {
        let identity = ControllableIdentity(VersionedProfile(profile: profileA, sequence: 0))
        let manager = makeUnboundedManager(identity: identity)
        let counter = CallCounter()
        let staleRelease = Latch()
        let staleObservation = CancellationObservation()
        let staleToken = try makeJWT(extraClaims: ["sub": "stale"])
        let freshToken = try makeJWT(extraClaims: ["sub": "fresh"])
        await manager.registerProvider {
            guard await counter.increment() == 1 else { return freshToken }
            await withTaskCancellationHandler {
                await staleRelease.wait()
            } onCancel: {
                Task { await staleRelease.open() }
            }
            await staleObservation.record(Task.isCancelled)
            return staleToken
        }
        try await counter.waitFor(atLeast: 1)
        let published = await manager.tokens()

        // The identity advances without the manager having seen it, so the rejected-token
        // refresh is the first to read the new generation.
        identity.setStaleRead(VersionedProfile(profile: profileB, sequence: 1))
        await manager.refreshRejectedToken()
        await staleRelease.open()
        let staleWasCancelled = await staleObservation.wait()

        #expect(staleWasCancelled, "the outgoing generation's fetch must be cancelled, not orphaned")
        let delivered = await firstElement(of: published)
        let invocations = await counter.value
        #expect(delivered == freshToken)
        #expect(invocations == 2)
    }
}
#endif
