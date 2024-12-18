//
//  AppLifeCycleEventsTests.swift
//
//
//  Created by Noah Durell on 12/15/22.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
@preconcurrency import Combine // Will figure out a better way for this...
import Foundation
import XCTest

@MainActor
class AppLifeCycleEventsTests: XCTestCase, Sendable {
    #if swift(>=6)
    nonisolated(unsafe) let passThroughSubject = PassthroughSubject<Notification, Never>()
    #else
    let passThroughSubject = PassthroughSubject<Notification, Never>()
    #endif

    func getFilteredNotificaitonPublished(name: Notification.Name) -> @Sendable (Notification.Name) -> AnyPublisher<Notification, Never> {
        // returns passthrough if it's match other return nothing
        { [self] notificationName in
            if name == notificationName {
                return passThroughSubject.eraseToAnyPublisher()
            } else {
                return Empty<Notification, Never>().eraseToAnyPublisher()
            }
        }
    }

    override func setUp() async throws {
        environment = KlaviyoEnvironment.test()
    }

    // MARK: - App Terminate

    func testAppTerminateStopsReachability() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.willTerminateNotification)
        let expection = XCTestExpectation(description: "Stop reachability is called.")
        let cancellable = AppLifeCycleEvents()
            .lifeCycleEvents(environment.notificationCenterPublisher, {}, { expection.fulfill() }, { .notReachable }).sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.willTerminateNotification.self))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testAppTerminateGetsStopAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.willTerminateNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, { .notReachable }).sink { action in
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
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, { expection.fulfill() }, { .notReachable }).sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didEnterBackgroundNotification.self))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testAppBackgroundGetsStopAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didEnterBackgroundNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, { .notReachable }).sink { action in
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
        #if swift(>=6)
        nonisolated(unsafe) var count = 0
        #else
        var count = 0
        #endif
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {
            if count == 0 {
                count += 1
            } else {
                expection.fulfill()
            }
        }, {}, { .notReachable }).sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testAppBecomeActiveGetsStartAction() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let stopActionExpection = XCTestExpectation(description: "Stop action is received.")
        stopActionExpection.assertForOverFulfill = true
        var receivedAction: KlaviyoAction?
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, { .notReachable }).sink { action in
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
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, { expection.fulfill() }, {}, { .notReachable }).sink { _ in }

        wait(for: [expection], timeout: 0.1)
        XCTAssertEqual(1, expection.expectedFulfillmentCount)
        cancellable.cancel()
    }

    // MARK: Reachability start failure

    func testReachabilityStartFailureIsHandled() {
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: UIApplication.didBecomeActiveNotification)
        let expection = XCTestExpectation(description: "Start reachability is called.")
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {
            expection.fulfill()
            throw KlaviyoAPIError.internalError("foo")
        }, {}, { .notReachable }).sink { _ in }

        passThroughSubject.send(Notification(name: UIApplication.didBecomeActiveNotification.self))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
        XCTAssertEqual(1, expection.expectedFulfillmentCount)
    }

    // MARK: Reachability notifications

    func testReachabilityNotificationStatusHandled() {
        let expection = XCTestExpectation(description: "Reachability status is accessed")
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: ReachabilityChangedNotification)
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, {
            expection.fulfill()
            return .reachableViaWWAN
        }).sink { _ in }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [expection], timeout: 0.1)
        cancellable.cancel()
    }

    func testReachabilityStatusNilThenNotNil() {
        let expection = XCTestExpectation(description: "Reachability status is accessed")
        environment.notificationCenterPublisher = getFilteredNotificaitonPublished(name: ReachabilityChangedNotification)
        #if swift(>=6)
        nonisolated(unsafe) var count = 0
        #else
        var count = 0
        #endif
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, {
            if count == 0 {
                count += 1
                return nil
            }
            expection.fulfill()
            return .reachableViaWWAN
        }).sink { _ in
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
        let cancellable = AppLifeCycleEvents().lifeCycleEvents(environment.notificationCenterPublisher, {}, {}, environment.reachabilityStatus).sink { action in
            receivedAction = action.transformToKlaviyoAction
            reachabilityAction.fulfill()
        }

        passThroughSubject.send(Notification(name: ReachabilityChangedNotification, object: Reachability()))

        wait(for: [reachabilityAction], timeout: 0.1)
        XCTAssertEqual(KlaviyoAction.networkConnectivityChanged(.reachableViaWWAN), receivedAction)
        cancellable.cancel()
    }
}
