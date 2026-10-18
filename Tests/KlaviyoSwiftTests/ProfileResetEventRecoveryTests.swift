@testable import KlaviyoSwift
import Combine
import KlaviyoCore
import XCTest

@MainActor
final class ProfileResetEventRecoveryTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        SharedStoreMirror.reset()
    }

    override func tearDown() {
        cancellables.removeAll()
        SharedStoreMirror.reset()
    }

    func testAnonymousResetRejectsHistoryQueuedDeliveryAndDeferredPublicationWithoutChangingIdentity() {
        let state = anonymousState()
        let store = Store(initialState: state, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { store.state.eraseToAnyPublisher() }
        SharedStoreMirror.setup()
        let origin = EventBus.shared.captureOrigin(apiKey: state.apiKey, identity: state.identity)
        var queued: [EventBus.Delivery] = []
        EventBus.shared.formEventPublisher(replayWindow: 0)
            .receive(on: DispatchQueue.main)
            .sink { queued.append($0) }
            .store(in: &cancellables)
        EventBus.shared.publish(Event(name: .customEvent("queued-before-reset")), origin: origin)

        _ = store.send(.resetProfile)
        XCTAssertEqual(IdentityStore.shared.current, state.identity)
        enrichAndPublishEvent(Event(name: .customEvent("deferred-before-reset")), origin: origin)
        var replay: [Event] = []
        EventBus.shared.eventPublisher().sink { replay.append($0) }.store(in: &cancellables)
        XCTAssertTrue(replay.isEmpty)
        let drained = expectation(description: "scheduled delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(queued.map(\.event.metric.name.value), ["queued-before-reset"])
        XCTAssertFalse(queued.contains { EventBus.shared.isCurrent($0) })
    }

    func testAnonymousIdentificationStillPreservesHistoryAndDeferredOrigin() {
        let state = anonymousState()
        let store = Store(initialState: state, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = { store.state.eraseToAnyPublisher() }
        SharedStoreMirror.setup()
        let origin = EventBus.shared.captureOrigin(apiKey: state.apiKey, identity: state.identity)
        EventBus.shared.publish(Event(name: .customEvent("anonymous-history")), origin: origin)
        _ = store.send(.setEmail("identified@example.com"))
        enrichAndPublishEvent(Event(name: .customEvent("anonymous-deferred")), origin: origin)
        var names: [String] = []
        EventBus.shared.eventPublisher().sink { names.append($0.metric.name.value) }.store(in: &cancellables)
        XCTAssertEqual(names, ["anonymous-history", "anonymous-deferred"])
        XCTAssertEqual(IdentityStore.shared.current.anonymousId, "anonymous-id")
    }

    func testUninitializedResetDoesNotInvalidateEvents() {
        var state = anonymousState()
        state.initalizationState = .uninitialized
        let store = Store(initialState: state, reducer: KlaviyoReducer())
        let origin = EventBus.shared.captureOrigin(apiKey: state.apiKey, identity: state.identity)
        EventBus.shared.publish(Event(name: .customEvent("history")), origin: origin)
        _ = store.send(.resetProfile)
        enrichAndPublishEvent(Event(name: .customEvent("deferred")), origin: origin)
        var names: [String] = []
        EventBus.shared.eventPublisher().sink { names.append($0.metric.name.value) }.store(in: &cancellables)
        XCTAssertEqual(names, ["history", "deferred"])
    }

    private func anonymousState() -> KlaviyoState {
        KlaviyoState(
            apiKey: "company", anonymousId: "anonymous-id", queue: [],
            requestsInFlight: [], initalizationState: .initialized
        )
    }
}
