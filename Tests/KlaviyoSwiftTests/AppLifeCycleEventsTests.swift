//
//  AppLifeCycleEventsTests.swift
//
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoSwift
import Combine
import Foundation
import KlaviyoCore
import XCTest

class AppLifeCycleEventsTests: XCTestCase {
    let passThroughSubject = PassthroughSubject<Notification, Never>()

    func getFilteredNotificationPublished(name: Notification.Name) -> (Notification.Name) -> AnyPublisher<Notification, Never> {
        // returns passthrough if it's match other return nothing
        { [weak self] notificationName in
            if name == notificationName {
                return self!.passThroughSubject.eraseToAnyPublisher()
            } else {
                return Empty<Notification, Never>().eraseToAnyPublisher()
            }
        }
    }

    @MainActor
    override func setUp() {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - App Terminate

    @MainActor
    func testAppTerminateStopsReachability() async {
        environment = KlaviyoEnvironment.test()
        let expectation = XCTestExpectation(description: "Stop reachability is called")
        environment.stopReachability = { expectation.fulfill() }

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let customLifeCycleEvents = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleSubject.eraseToAnyPublisher()
        })

        environment.appLifeCycle = customLifeCycleEvents
        let cancellable = environment.lifecycleEventsWithReachability().sink { _ in }

        lifecycleSubject.send(.terminated)
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAppTerminateEmitsTerminatedEvent() {
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: UIApplication.willTerminateNotification)
        let terminatedExpectation = XCTestExpectation(description: "Terminated lifecycle event is received.")
        terminatedExpectation.assertForOverFulfill = true
        var receivedEvent: LifeCycleEvents?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { event in
            receivedEvent = event
            terminatedExpectation.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.willTerminateNotification.self))

        wait(for: [terminatedExpectation], timeout: 0.1)
        guard case .terminated = receivedEvent else {
            return XCTFail("expected .terminated, got \(String(describing: receivedEvent))")
        }
        cancellable.cancel()
    }

    // MARK: - App Background

    func testAppBackgroundStopsReachability() async {
        environment = KlaviyoEnvironment.test()
        let expectation = XCTestExpectation(description: "Stop reachability is called")
        environment.stopReachability = { expectation.fulfill() }
        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let customLifeCycleEvents = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleSubject.eraseToAnyPublisher()
        })

        environment.appLifeCycle = customLifeCycleEvents
        let cancellable = environment.lifecycleEventsWithReachability().sink { _ in }
        lifecycleSubject.send(.backgrounded)

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAppBackgroundEmitsBackgroundedEvent() {
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: UIApplication.didEnterBackgroundNotification)
        let backgroundedExpectation = XCTestExpectation(description: "Backgrounded lifecycle event is received.")
        backgroundedExpectation.assertForOverFulfill = true
        var receivedEvent: LifeCycleEvents?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { event in
            receivedEvent = event
            backgroundedExpectation.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.didEnterBackgroundNotification.self))

        wait(for: [backgroundedExpectation], timeout: 0.1)
        guard case .backgrounded = receivedEvent else {
            return XCTFail("expected .backgrounded, got \(String(describing: receivedEvent))")
        }
        cancellable.cancel()
    }

    // MARK: - Did become active

    func testAppBecomesActiveStartsReachibility() async {
        environment = KlaviyoEnvironment.test()
        let expectation = XCTestExpectation(description: "Start reachability is called")
        environment.startReachability = { expectation.fulfill() }

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let customLifeCycleEvents = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleSubject.eraseToAnyPublisher()
        })
        environment.appLifeCycle = customLifeCycleEvents
        let cancellable = environment.lifecycleEventsWithReachability().sink { _ in }

        lifecycleSubject.send(.foregrounded)
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testAppBecomeActiveEmitsForegroundedEvent() {
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: UIApplication.didBecomeActiveNotification)
        let foregroundedExpectation = XCTestExpectation(description: "Foregrounded lifecycle event is received.")
        foregroundedExpectation.assertForOverFulfill = true
        var receivedEvent: LifeCycleEvents?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { event in
            receivedEvent = event
            foregroundedExpectation.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [foregroundedExpectation], timeout: 0.1)
        guard case .foregrounded = receivedEvent else {
            return XCTFail("expected .foregrounded, got \(String(describing: receivedEvent))")
        }
        cancellable.cancel()
    }

    // MARK: Reachability start failure

    func testReachabilityStartFailureIsHandled() async {
        environment = KlaviyoEnvironment.test()
        let expectation = XCTestExpectation(description: "Start reachability is called")
        environment.startReachability = {
            expectation.fulfill()
            throw KlaviyoAPIError.internalError("foo")
        }

        let lifecycleSubject = PassthroughSubject<LifeCycleEvents, Never>()
        let customLifeCycleEvents = AppLifeCycleEvents(lifeCycleEvents: {
            lifecycleSubject.eraseToAnyPublisher()
        })
        environment.appLifeCycle = customLifeCycleEvents
        let cancellable = environment.lifecycleEventsWithReachability().sink { _ in }

        lifecycleSubject.send(.foregrounded)
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
        XCTAssertEqual(1, expectation.expectedFulfillmentCount)
    }

    // MARK: Reachability notifications

    func testReachabilityNotificationStatusHandled() {
        let expection = XCTestExpectation(description: "Reachability status is accessed")
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: ReachabilityChangedNotification)
        environment.reachabilityStatus = {
            expection.fulfill()
            return .reachableViaWWAN
        }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testReachabilityStatusNilThenNotNil() {
        let expection = XCTestExpectation(description: "Reachability status is accessed")
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: ReachabilityChangedNotification)
        var count = 0
        environment.reachabilityStatus = {
            if count == 0 {
                count += 1
                return nil
            }
            expection.fulfill()
            return .reachableViaWWAN
        }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in
            XCTFail()
        } receiveValue: { _ in }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))
        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testReachaibilityNotificationEmitsReachabilityChangedEvent() {
        environment.reachabilityStatus = { .reachableViaWWAN }
        environment.notificationCenterPublisher = getFilteredNotificationPublished(name: ReachabilityChangedNotification)
        let reachabilityExpectation = XCTestExpectation(description: "Reachabilty changed is received.")
        var receivedEvent: LifeCycleEvents?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { event in
            receivedEvent = event
            reachabilityExpectation.fulfill()
        }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [reachabilityExpectation], timeout: 0.1)
        guard case let .reachabilityChanged(status) = receivedEvent else {
            return XCTFail("expected .reachabilityChanged, got \(String(describing: receivedEvent))")
        }
        XCTAssertEqual(status, .reachableViaWWAN)
        cancellable.cancel()
    }
}
