//
//  StateChangePublisherTests.swift
//
//
//  Created by Noah Durell on 12/21/22.
//

import Combine
import CombineSchedulers
import Foundation
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import KlaviyoCore

final class StateChangePublisherTests: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
    }

    // NOTE: the former `testStateChangePublisher`, `testStateChangeDuplicateAreRemoved`, and
    // `testQuickStateUpdatesTriggerOnlyOneSaves` tests exercised the debounced save `publisher`
    // path (`StateChangePublisher.debouncedPublisher` + `saveKlaviyoState`). All three were
    // deleted in Task 5: the save path (`debouncedPublisher`, `var publisher`) no longer exists
    // and `KlaviyoState` is non-Codable. `internalStatePublisher` coverage is below.

    @MainActor
    func testInternalStatePublisherEmitsAfterInitialization() throws {
        let expectation = XCTestExpectation(description: "internalStatePublisher emits state")

        // `KlaviyoState.test` starts initialized with `email: "test@test.com"`.
        // Wire the testStore's state as the source so `internalStatePublisher` sees it.
        let testStore = Store(initialState: KlaviyoState.test, reducer: KlaviyoTestReducer())
        let previousStatePublisher = klaviyoSwiftEnvironment.statePublisher
        defer { klaviyoSwiftEnvironment.statePublisher = previousStatePublisher }
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        var cancellables = Set<AnyCancellable>()
        StateChangePublisher.internalStatePublisher()
            .first()
            .sink { privateState in
                // Verify the publisher projects state correctly.
                XCTAssertEqual(privateState.email, KlaviyoState.test.email)
                XCTAssertNotNil(privateState.anonymousId)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}
