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
    func testAppTerminateStopsReachability() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.willTerminateNotification)
        let expection = XCTestExpectation(description: "Stop reachability is called.")
        environment.stopReachability = { expection.fulfill() }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.willTerminateNotification.self))

        wait(for: [expection], timeout: 0.1)
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

    func testAppBackgroundStopsReachability() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didEnterBackgroundNotification)
        let expection = XCTestExpectation(description: "Stop reachability is called.")
        environment.stopReachability = { expection.fulfill() }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didEnterBackgroundNotification.self))

        wait(for: [expection], timeout: 0.1)
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

    func testAppBecomesActiveStartsReachibility() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let expection = XCTestExpectation(description: "Start reachability is called.")
        var count = 0
        environment.startReachability = {
            if count == 0 {
                count += 1
            } else {
                expection.fulfill()
            }
        }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [expection], timeout: 0.1)
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

    func testStartReachabilityCalledOnSubscription() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let expection = XCTestExpectation(description: "Start reachability is called.")
        expection.assertForOverFulfill = true
        environment.startReachability = { expection.fulfill() }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        wait(for: [expection], timeout: 0.1)
        XCTAssertEqual(1, expection.expectedFulfillmentCount)
        cancellable.cancel()
    }

    // MARK: Reachability start failure

    func testReachabilityStartFailureIsHandled() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let expection = XCTestExpectation(description: "Start reachability is called.")
        environment.startReachability = {
            expection.fulfill()
            throw KlaviyoAPIError.internalError("foo")
        }
        let cancellable = AppLifeCycleEvents().lifeCycleEvents().sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
        XCTAssertEqual(1, expection.expectedFulfillmentCount)
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
