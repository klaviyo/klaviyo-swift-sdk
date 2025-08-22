//
//  IAFPresentationManagerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//

@testable import KlaviyoForms
import Combine
import Foundation
import KlaviyoCore
import OSLog
import UIKit
import WebKit
import XCTest
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift

final class IAFPresentationManagerTests: XCTestCase {
    // MARK: - setup

    fileprivate var presentationManager: MockIAFPresentationManager!
    fileprivate var mockViewController: MockKlaviyoWebViewController!
    fileprivate var mockViewModel: MockIAFWebViewModel!
    var mockLifecycleEvents: PassthroughSubject<LifeCycleEvents, Never>!
    var mockApiKeyPublisher: PassthroughSubject<String?, Never>!
    var cancellables: Set<AnyCancellable> = []

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        mockViewModel = MockIAFWebViewModel(url: URL(string: "https://example.com")!)
        mockViewController = MockKlaviyoWebViewController(viewModel: mockViewModel)
        mockLifecycleEvents = PassthroughSubject<LifeCycleEvents, Never>()
        mockApiKeyPublisher = PassthroughSubject<String?, Never>()

        environment = KlaviyoEnvironment.test()
        environment.appLifeCycle = AppLifeCycleEvents(lifeCycleEvents: {
            self.mockLifecycleEvents.eraseToAnyPublisher()
        })

        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())

        mockApiKeyPublisher
            .compactMap { $0 }
            .sink { apiKey in
                _ = testStore.send(.initialize(apiKey))
            }
            .store(in: &cancellables)

        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        presentationManager = MockIAFPresentationManager(viewController: mockViewController)
        mockApiKeyPublisher.send("setup-key") // initialize SDK
//        try await Task.sleep(nanoseconds: 100_000_000)
    }

    override func tearDown() {
        presentationManager = nil
        mockViewController = nil
        mockViewModel = nil
        mockLifecycleEvents = nil
        mockApiKeyPublisher = nil
        cancellables.removeAll()
        KlaviyoInternal.resetAPIKeySubject()
        KlaviyoInternal.resetProfileDataSubject()
        super.tearDown()
    }

    // MARK: - tests

    @MainActor
    func testDispatchEventInjection() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event is injected")
        presentationManager.initializeIAF(configuration: InAppFormsConfig())
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        try await presentationManager.handleLifecycleEvent("test")

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('test')")
        })
    }

    @MainActor
    func testBackgroundForegroundLifecycleEventsInjected() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // When
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertEqual(presentationManager.handledEvents, ["background", "foreground"], "Background and foreground event should be handled")
    }

    @MainActor
    func testForegroundEvent_WithinSession_KeepsViewControllerAlive() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        // Wait for initial setup creating webview to complete and reset flags
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormAndAwaitFormEventsCalled = false

        // When
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        mockLifecycleEvents.send(.foregrounded)

        // Then
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should not be destroyed when foregrounding within session")
        XCTAssertFalse(presentationManager.createFormAndAwaitFormEventsCalled, "Web view should not be recreated when foregrounding within session")
    }

    @MainActor
    func testForegroundEvent_InNewSession_DestroysViewController() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        // Wait for initial setup creating webview to complete and reset flags
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormAndAwaitFormEventsCalled = false

        let destroyExpectation = XCTestExpectation(description: "Web view is destroyed on new session")
        let createExpectation = XCTestExpectation(description: "Web view is created on new session")
        presentationManager.destroyWebviewExpectation = destroyExpectation
        presentationManager.createFormAndAwaitFormEventsExpectation = createExpectation

        // When
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [destroyExpectation, createExpectation], timeout: 5.0)
        XCTAssertTrue(presentationManager.destroyWebviewCalled, "Web view should be destroyed when foregrounding in new session")
    }

    @MainActor
    func testForegroundNewLaunchCreatesNewViewController() async throws {
        // Given
        let createExpectation = XCTestExpectation(description: "Web view is created on new session")
        presentationManager.createFormAndAwaitFormEventsExpectation = createExpectation
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Web view should be recreated when foregrounding in new session")
    }

    @MainActor
    func testIntializeApiKeyChangeCreatesNewViewController() async throws {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.initializeIAF(configuration: InAppFormsConfig())

        // When
        mockApiKeyPublisher.send("new-key")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.destroyWebviewCalled, "destroyWebview should be called when api key changes")
        XCTAssertTrue(mockManager.createFormAndAwaitFormEventsCalled, "createFormAndAwaitFormEvents should be called when foregrounding in new session")
    }

    @MainActor
    func testDestroyWebviewAndListenersCleansUpLifecycleSubscription() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event script is not injected after destroying listener")
        presentationManager.initializeIAF(configuration: InAppFormsConfig())
        expectation.isInverted = true

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }
        presentationManager.destroyWebviewAndListeners()

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.isEmpty, "Unexpected script evaluation: \(evaluatedScripts)")
    }

    @MainActor
    func testDestroyWebviewAndListenersCleansUpApiKeySubscription() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event script is not injected after destroying listener")
        presentationManager.initializeIAF(configuration: InAppFormsConfig())
        expectation.isInverted = true

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }
        presentationManager.destroyWebviewAndListeners()

        // When
        mockApiKeyPublisher.send("ABC123")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.isEmpty, "Unexpected script evaluation: \(evaluatedScripts)")
    }

    // MARK: - Session Timeout Tests

    @MainActor
    func testNegativeSessionTimeoutDurationIsNormalizedToZero() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Form is recreated after session timeout")
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        // When
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: -1))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Form should be recreated immediately when using negative timeout duration")
    }

    @MainActor
    func testZeroSessionTimeoutDurationResetsImmediately() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Form is recreated after session timeout")
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        // When
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 0))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.destroyWebviewCalled, "Web view should be destroyed when foregrounding in new session")
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Form should be recreated immediately when using zero timeout duration")
    }

    @MainActor

    func testInfiniteSessionTimeoutDurationNeverResets() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: .infinity))

        // Wait for initial setup to complete and reset flags
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormAndAwaitFormEventsCalled = false
        let expectation = XCTestExpectation(description: "Form is not recreated after session timeout")
        expectation.isInverted = true
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should never be destroyed when foregrounding in an infinite session")
        XCTAssertFalse(presentationManager.createFormAndAwaitFormEventsCalled, "Form should never be recreated")
    }
}

// MARK: - Mock Classes

private final class MockKlaviyoWebViewController: KlaviyoWebViewController {
    var evaluateJavaScriptCallback: ((String) -> Any)?

    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        evaluateJavaScriptCallback?(script)
    }
}

private final class MockIAFWebViewModel: KlaviyoWebViewModeling {
    var messageHandlers: Set<String>?

    var url: URL
    weak var delegate: KlaviyoWebViewDelegate?
    var loadScripts: Set<WKUserScript>?

    init(url: URL) {
        self.url = url
    }

    func handleNavigationEvent(_ event: KlaviyoForms.WKNavigationEvent) {}
    func handleScriptMessage(_ message: WKScriptMessage) {}
}

private final class MockIAFPresentationManager: IAFPresentationManager {
    var createFormAndAwaitFormEventsCalled = false
    var destroyWebviewCalled = false
    var formEventTask: Task<Void, Never>?
    var destroyWebviewExpectation: XCTestExpectation?
    var createFormAndAwaitFormEventsExpectation: XCTestExpectation?
    var handleLifecycleEventExpectation: XCTestExpectation?
    var handledEvents: [String] = []

    override func createFormAndAwaitFormEvents(apiKey: String) async throws {
        createFormAndAwaitFormEventsCalled = true
        createFormAndAwaitFormEventsExpectation?.fulfill()
        try await super.createFormAndAwaitFormEvents(apiKey: apiKey)
    }

    override func destroyWebView() {
        destroyWebviewCalled = true
        destroyWebviewExpectation?.fulfill()
        super.destroyWebView()
    }

    override func dismissForm() {
        destroyWebviewCalled = true
        super.destroyWebView()
    }

    override func handleLifecycleEvent(_ event: String) async throws {
        handledEvents.append(event)
        handleLifecycleEventExpectation?.fulfill()
        try await super.handleLifecycleEvent(event)
    }
}
