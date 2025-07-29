@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

@MainActor
final class AttemptNumberTests: XCTestCase {
    func testFirstRequestStartsAtOne() async throws {
        var capturedAttempt: Int?
        environment.klaviyoAPI.send = { _, attemptInfo in
            capturedAttempt = attemptInfo.attemptNumber
            return .success(Data())
        }

        // Build a minimal request and pre-populate state with it in flight.
        let request = KlaviyoRequest(apiKey: "foo", endpoint: .createEvent(.init(data: .init(name: "foo"))))
        let initialState = KlaviyoState(
            apiKey: "foo",
            anonymousId: environment.uuid().uuidString,
            queue: [],
            requestsInFlight: [request],
            initalizationState: .initialized,
            flushing: true
        )

        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off // We only care about the sendRequest action.

        // Trigger sendRequest which should invoke our mock API.
        await store.send(.sendRequest)

        XCTAssertEqual(capturedAttempt, 1, "The first request should have an attempt number of 1")
    }
}
