import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Combine
import KlaviyoCore

class StateChangePublisherTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        cancellables = []
        environment = KlaviyoEnvironment.test()
    }

    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        super.tearDown()
    }

    func testPublisherCallsSaveKlaviyoState() {
        let expectation = XCTestExpectation(description: "Wait for publisher to call saveKlaviyoState")

        // Create a mock state to publish
        let mockState = INITIALIZED_TEST_STATE()

        // Set up a flag to verify saveKlaviyoState was called
        var saveKlaviyoStateCalled = false

        environment.fileClient.write = { _, _ in
            saveKlaviyoStateCalled = true
            expectation.fulfill()
        }

        // Use a PassthroughSubject to simulate the statePublisher
        let stateSubject = PassthroughSubject<KlaviyoState, Never>()

        // Mock the klaviyoSwiftEnvironment to use the stateSubject as the publisher
        klaviyoSwiftEnvironment.statePublisher = { stateSubject.eraseToAnyPublisher() }

        // Use a TestScheduler to control time
        let testScheduler = DispatchQueue.test

        // Override the debouncedPublisher to use the test scheduler
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(1), scheduler: testScheduler)
                .eraseToAnyPublisher()
        }

        StateChangePublisher().publisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                // This block won't execute because the publisher returns an Empty publisher.
                // We're testing the side effect of saveKlaviyoState being called.
            })
            .store(in: &cancellables)

        // Send the mock state
        stateSubject.send(mockState)

        // Advance time to trigger a save
        testScheduler.advance(by: .seconds(1))

        XCTAssertTrue(saveKlaviyoStateCalled, "Expected saveKlaviyoState to be called")

        wait(for: [expectation], timeout: 2.0)

        saveKlaviyoStateCalled = false

        environment.fileClient.write = { _, _ in
            saveKlaviyoStateCalled = true
        }

        // Send the mock state again
        stateSubject.send(mockState)

        testScheduler.advance(by: .seconds(1))

        XCTAssertFalse(saveKlaviyoStateCalled, "Expected saveKlaviyoState NOT to be called")
    }
}
