import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Combine
import KlaviyoCore

// TODO: follow up on these change - ensure we are still testing edge cases here

@MainActor
class StateChangePublisherTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() async throws {
        cancellables = []
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
    }

    override func tearDown() async throws {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func testPublisherCallsEmitsOnlyOnce() async {
        // Create a mock state to publish
        let mockState = INITIALIZED_TEST_STATE()

        // Use a PassthroughSubject to simulate the statePublisher
        let stateSubject = PassthroughSubject<KlaviyoState, Never>()

        // Mock the klaviyoSwiftEnvironment to use the stateSubject as the publisher
        klaviyoSwiftEnvironment.statePublisher = {
            stateSubject.eraseToAnyPublisher()
        }

        // Use a TestScheduler to control time
        let testScheduler = DispatchQueue.test

        // Override the debouncedPublisher to use the test scheduler
        StateChangePublisher.debouncedPublisher = { publisher in
            publisher
                .debounce(for: .seconds(1), scheduler: testScheduler)
                .eraseToAnyPublisher()
        }

        let expectation = XCTestExpectation(description: "Publisher emits once")
        expectation.expectedFulfillmentCount = 1
        var count = 0

        Task {
            for await _ in StateChangePublisher().publisher() {
                count += 1
                expectation.fulfill()
            }
        }

        // Send the mock state
        stateSubject.send(mockState)

        // Advance time to trigger the debounced emission
        await testScheduler.advance(by: .seconds(1.1))

        // Send the mock state again (should not cause a new emission)
        stateSubject.send(mockState)

        // Advance time again to process any pending events
        await testScheduler.advance(by: .seconds(1.1))

        // Wait for expectation or timeout
        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertEqual(count, 1)
    }
}
