//
//  KlaviyoInternalTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/22/25.
//

import Combine
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import KlaviyoCore

final class KlaviyoInternalTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    @MainActor
    override func tearDownWithError() throws {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    @MainActor
    func testProfileChangePublisherEmitsCorrectData() throws {
        let expectation = XCTestExpectation(description: "Profile data is emitted")
        var receivedProfile: ProfileData?

        // Set up test environment
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        // Subscribe to the publisher
        KlaviyoInternal.profileChangePublisher()
            .sink { profile in
                receivedProfile = profile
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger a profile change
        _ = testStore.send(.setEmail("a@b.com"))
        _ = testStore.send(.setPhoneNumber("+15555555555"))
        _ = testStore.send(.setExternalId("test123"))

        // Wait for the expectation
        wait(for: [expectation], timeout: 1.0)

        // Verify the emitted profile data
        XCTAssertEqual(receivedProfile?.email, "a@b.com")
        XCTAssertEqual(receivedProfile?.phoneNumber, "+15555555555")
        XCTAssertEqual(receivedProfile?.externalId, "test123")
    }

    @MainActor
    func testRemoveDuplicates() throws {
        let expectation = XCTestExpectation(description: "Profile data is emitted")
        var receiveValueCount = 0

        // Set up test environment
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let initialEmail = try XCTUnwrap(KlaviyoState.test.email)

        // Subscribe to the publisher
        KlaviyoInternal.profileChangePublisher()
            .sink { _ in
                receiveValueCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // receiveValueCount should be 1 at this point because `profileChangePublisher`
        // will get an initial value when it receives a subscription.
        XCTAssertEqual(receiveValueCount, 1)

        // Trigger a profile change
        _ = testStore.send(.setEmail(initialEmail))

        // receiveValueCount should stay at 1 because we
        // set the email to the same as its initial value
        XCTAssertEqual(receiveValueCount, 1)

        // Wait for the expectation
        wait(for: [expectation], timeout: 1.0)
    }
}
