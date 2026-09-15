//
//  StateChangePublisherTests.swift
//
//
//  Created by Noah Durell on 12/21/22.
//

@testable import KlaviyoCore
import Combine
import Foundation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

final class StateChangePublisherTests: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()
    }

    @MainActor
    override func tearDown() async throws {
        LifecycleState.shared.reset()
    }

    // NOTE: the former `testStateChangePublisher`, `testStateChangeDuplicateAreRemoved`, and
    // `testQuickStateUpdatesTriggerOnlyOneSaves` tests exercised the debounced save `publisher`
    // path (`StateChangePublisher.debouncedPublisher` + `saveKlaviyoState`). All three were
    // deleted in Task 5: the save path (`debouncedPublisher`, `var publisher`) no longer exists
    // and `KlaviyoState` is non-Codable. `internalStatePublisher` coverage is below.

    @MainActor
    func testInternalStatePublisherEmitsAfterInitialization() throws {
        let expectation = XCTestExpectation(description: "internalStatePublisher emits state")

        // Seed the canonical identity store, then advance the lifecycle to `.initialized` so the
        // publisher (gated on `.initialized`) emits.
        IdentityStore.shared.update(ProfileData(
            email: "test@test.com",
            anonymousId: environment.uuid().uuidString
        ))
        LifecycleState.shared.beginInitializing()

        var cancellables = Set<AnyCancellable>()
        StateChangePublisher.internalStatePublisher()
            .first()
            .sink { privateState in
                // Verify the publisher projects identity correctly.
                XCTAssertEqual(privateState.email, "test@test.com")
                XCTAssertNotNil(privateState.anonymousId)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Transition to `.initialized` after subscribing so the `.filter { $0.2 == .initialized }`
        // gate opens and the CombineLatest3 delivers.
        LifecycleState.shared.completeInitialization()

        wait(for: [expectation], timeout: 1.0)
    }
}
