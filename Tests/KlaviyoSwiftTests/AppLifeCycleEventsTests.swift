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

    func getFilteredNotificaitonPublished(name: Notification.Name) -> (Notification.Name) -> AnyPublisher<Notification, Never> {
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

    func testAppTerminateGetsStopAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.willTerminateNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { action in
            receivedAction = action.transformToKlaviyoAction
            stopActionExpection.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.willTerminateNotification.self))

        wait(for: [stopActionExpection], timeout: 0.1)
        XCTAssertEqual(KlaviyoAction.stop, receivedAction)
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

    func testAppBackgroundGetsStopAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didEnterBackgroundNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { action in
            receivedAction = action.transformToKlaviyoAction
            stopActionExpection.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.didEnterBackgroundNotification.self))

        wait(for: [stopActionExpection], timeout: 0.1)
        XCTAssertEqual(KlaviyoAction.stop, receivedAction)
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

    func testAppBecomeActiveGetsStartAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { action in
            receivedAction = action.transformToKlaviyoAction
            stopActionExpection.fulfill()
        }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [stopActionExpection], timeout: 0.1)
        XCTAssertEqual(KlaviyoAction.start, receivedAction)
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
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: ReachabilityChangedNotification)
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
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: ReachabilityChangedNotification)
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

    func testReachaibilityNotificationGetsRightAction() {
        environment.reachabilityStatus = { .reachableViaWWAN }
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: ReachabilityChangedNotification)
        let reachabilityAction = XCTestExpectation(description: "Reachabilty changed is received.")
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { action in
            receivedAction = action.transformToKlaviyoAction
            reachabilityAction.fulfill()
        }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [reachabilityAction], timeout: 0.1)
        XCTAssertEqual(KlaviyoAction.networkConnectivityChanged(.reachableViaWWAN), receivedAction)
        cancellable.cancel()
    }
}
