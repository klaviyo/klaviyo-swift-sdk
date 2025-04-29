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

    // MARK: - apiKeyPublisher tests

    func testApiKeyPublisher_emitsValidKeyImmediately() {
        let expectation = XCTestExpectation(description: "Should receive valid key immediately")
        var receivedValues: [String] = []

        // Set up the test environment with a valid key
        let initialState = KlaviyoState(apiKey: "ABC123", queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.apiKeyPublisher()
            .sink { apiKey in
                receivedValues.append(apiKey)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, ["ABC123"])
    }

    func testApiKeyPublisher_emitsMultipleValues() {
        let expectation = XCTestExpectation(description: "Publisher should emit two API keys")
        var receivedValues = Set<String>()

        // Set up the test environment with a valid key
        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        KlaviyoInternal.apiKeyPublisher()
            .sink { apiKey in
                receivedValues.insert(apiKey)
                if receivedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = testStore.send(.initialize("ABC123"))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            _ = testStore.send(.initialize("DEF456"))
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, Set<String>(["ABC123", "DEF456"]))
    }

    func testApiKeyPublisher_willNotEmitNilAPIKey() async {
        // Set up the test environment with a nil key
        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let expectation = XCTestExpectation(description: "Publisher should not emit any values")
        expectation.isInverted = true // fails the test if the expectation is fulfilled

        KlaviyoInternal.apiKeyPublisher()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Wait for a short time to ensure no values are emitted
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testApiKeyPublisher_willNotEmitEmptyAPIKey() {
        // Set up the test environment with an empty key
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }
        _ = testStore.send(.initialize(""))

        let expectation = XCTestExpectation(description: "Publisher should not emit any values")
        expectation.isInverted = true // fails the test if the expectation is fulfilled

        KlaviyoInternal.apiKeyPublisher()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}
