//
//  SharedStoreMirrorTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

final class SharedStoreMirrorTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    @MainActor
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        SharedStoreMirror.reset()
    }

    @MainActor
    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        SharedStoreMirror.reset()
        super.tearDown()
    }

    @MainActor
    func testSetupSharedStoresPushesIdentityOnChange() throws {
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        SharedStoreMirror.setup()

        _ = testStore.send(.setEmail("wired@example.com"))

        let expectation = XCTestExpectation(description: "IdentityStore reflects email")
        DispatchQueue.main.async {
            XCTAssertEqual(IdentityStore.shared.current.email, "wired@example.com")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testSetupSharedStoresPushesAPIKeyOnChange() throws {
        // `.test` state is already `.initialized` with apiKey "foo".
        let testStore = Store(initialState: .test, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { testStore.state.eraseToAnyPublisher() }

        let expectation = XCTestExpectation(description: "SDKConfigStore reflects api key")
        SDKConfigStore.shared.publisher
            .dropFirst() // skip the CurrentValueSubject's initial emission
            .sink { config in
                if config.apiKey == "foo" { expectation.fulfill() }
            }
            .store(in: &cancellables)

        SharedStoreMirror.setup()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(SDKConfigStore.shared.current.apiKey, "foo")
    }
}
