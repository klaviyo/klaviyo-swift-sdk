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

    // MARK: - Helper Methods

    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment

        // List of common CI environment variables to check
        let ciVariables = [
            "TEST_RUNNER_GITHUB_CI",
            "GITHUB_ACTIONS",
            "GITHUB_CI",
            "CI"
        ]

        // Check each variable - consider it CI if the variable exists and has a truthy value
        for variable in ciVariables {
            if let value = env[variable], !value.isEmpty {
                let isTruthy = value.lowercased() == "true" || value == "1" || value.lowercased() == "yes"
                if isTruthy {
                    return true
                }
            }
        }

        // Additional check: GITHUB_ACTIONS is always present in GitHub Actions
        // If we're in GitHub Actions, we're definitely in CI
        if env["GITHUB_ACTIONS"] != nil {
            return true
        }

        return false
    }

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
        try await Task.sleep(nanoseconds: 200_000_000) // wait for initialization to be completed
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
        let backgroundExpectation = XCTestExpectation(description: "Background event handled")
        let foregroundExpectation = XCTestExpectation(description: "Foreground event handled")

        // Setup expectations tracking BEFORE initialization to avoid race conditions
        var originalEvaluateCallback = mockViewController.evaluateJavaScriptCallback
        mockViewController.evaluateJavaScriptCallback = { script in
            if script.contains("dispatchLifecycleEvent('background')") {
                backgroundExpectation.fulfill()
            } else if script.contains("dispatchLifecycleEvent('foreground')") {
                foregroundExpectation.fulfill()
            }
            return originalEvaluateCallback?(script) ?? true
        }

        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds - wait for webview to be ready

        // When
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds - allow time for event processing
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [backgroundExpectation, foregroundExpectation], timeout: 5.0)
        XCTAssertEqual(presentationManager.handledEvents, ["background", "foreground"], "Background and foreground event should be handled")
    }

    @MainActor
    func testForegroundEvent_WithinSession_KeepsViewControllerAlive() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
        // Wait for initial setup creating webview to complete and reset flags
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormWebViewAndListenCalled = false

        // When
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds - allow time for processing

        // Then
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should not be destroyed when foregrounding within session")
        XCTAssertFalse(presentationManager.createFormWebViewAndListenCalled, "Web view should not be recreated when foregrounding within session")
    }

    @MainActor
    func testForegroundEvent_InNewSession_DestroysViewController() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
        // Wait for initial setup creating webview to complete and reset flags
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormWebViewAndListenCalled = false

        let destroyExpectation = XCTestExpectation(description: "Web view is destroyed on new session")
        let createExpectation = XCTestExpectation(description: "Web view is created on new session")
        presentationManager.destroyWebviewExpectation = destroyExpectation
        presentationManager.createFormWebViewAndListenExpectation = createExpectation

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
        presentationManager.createFormWebViewAndListenExpectation = createExpectation
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [createExpectation], timeout: 2.0)
        XCTAssertTrue(presentationManager.createFormWebViewAndListenCalled, "Web view should be recreated when foregrounding in new session")
    }

    @MainActor
    func testIntializeApiKeyChangeCreatesNewViewController() async throws {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.initializeIAF(configuration: InAppFormsConfig())
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

        // Wait for initial webview creation to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // When
        mockApiKeyPublisher.send("new-key")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.destroyWebviewCalled, "destroyWebview should be called when api key changes")
        XCTAssertTrue(mockManager.createFormWebViewAndListenCalled, "createFormWebViewAndListen should be called when foregrounding in new session")
    }

    @MainActor
    func testDestroyWebviewAndListenersCleansUpLifecycleSubscription() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event script is not injected after destroying listener")
        presentationManager.initializeIAF(configuration: InAppFormsConfig())
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        presentationManager.createFormWebViewAndListenExpectation = expectation

        // When
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: -1))
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.createFormWebViewAndListenCalled, "Form should be recreated immediately when using negative timeout duration")
    }

    @MainActor
    func testZeroSessionTimeoutDurationResetsImmediately() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Form is recreated after session timeout")
        presentationManager.createFormWebViewAndListenExpectation = expectation

        // When
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 0))
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.destroyWebviewCalled, "Web view should be destroyed when foregrounding in new session")
        XCTAssertTrue(presentationManager.createFormWebViewAndListenCalled, "Form should be recreated immediately when using zero timeout duration")
    }

    @MainActor
    func testInfiniteSessionTimeoutDurationNeverResets() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: .infinity))
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

        // Wait for initial setup to complete and reset flags
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        presentationManager.destroyWebviewCalled = false
        presentationManager.createFormWebViewAndListenCalled = false
        let expectation = XCTestExpectation(description: "Form is not recreated after session timeout")
        expectation.isInverted = true
        presentationManager.createFormWebViewAndListenExpectation = expectation

        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds - allow time for processing

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should never be destroyed when foregrounding in an infinite session")
        XCTAssertFalse(presentationManager.createFormWebViewAndListenCalled, "Form should never be recreated")
    }

    // MARK: - Profile Event Injection Tests

    @MainActor
    func testHandleProfileEventCreatedInjectsEvent() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event is handled successfully")
        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchProfileEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        let testEvent = Event(name: .addedToCartMetric, properties: ["amount": 99.99, "currency": "USD"])
        try await presentationManager.handleProfileEventCreated(testEvent)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchProfileEvent") && script.contains("Added to Cart")
        }, "Event should be dispatched with correct event name")

        // Verify properties are passed as JSON object (not string)
        let scriptWithProperties = evaluatedScripts.first { script in
            script.contains("dispatchProfileEvent") && script.contains("Added to Cart")
        }
        XCTAssertNotNil(scriptWithProperties, "Should find script with dispatchProfileEvent")

        if let script = scriptWithProperties {
            // Properties should be passed as JSON object, not quoted string
            XCTAssertTrue(script.contains("\"amount\":"), "Properties should include amount key")
            XCTAssertTrue(script.contains("\"currency\":"), "Properties should include currency key")
            XCTAssertTrue(script.contains("USD"), "Properties should include USD value")
            XCTAssertFalse(script.contains("'{\"amount\":99.99,\"currency\":\"USD\"}'"), "Properties should not be wrapped in quotes")
        }
    }

    @MainActor
    func testEventSubscriptionCleanup() async throws {
        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig())
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization

        // When
        presentationManager.destroyWebviewAndListeners()

        // Then
        // Create and publish an event after cleanup
        let testEvent = Event(name: .customEvent("test_event"), properties: ["key": "value"])
        KlaviyoInternal.publishEvent(testEvent)

        // Should not crash or cause issues
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    // MARK: - Event Replay Tests

    @MainActor
    func testEventsDispatchedDirectlyWhenWebviewReady() async throws {
        // Given - viewController already exists from setUp
        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            return true
        }

        // When - Send event when viewController exists
        let event = Event(name: .viewedProductMetric, properties: ["product_id": "789"])
        try await presentationManager.handleProfileEventCreated(event)

        try await Task.sleep(nanoseconds: 100_000_000) // Wait for async dispatch

        // Then - Event should be dispatched immediately (no buffering at this level)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchProfileEvent") && script.contains("Viewed Product")
        }, "Event should be dispatched immediately when webview exists")
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
    var createFormWebViewAndListenCalled = false
    var destroyWebviewCalled = false
    var formEventTask: Task<Void, Never>?
    var destroyWebviewExpectation: XCTestExpectation?
    var createFormWebViewAndListenExpectation: XCTestExpectation?
    var handledEvents: [String] = []

    override init(viewController: KlaviyoWebViewController?) {
        super.init(viewController: viewController)
    }

    override func createFormWebViewAndListen(apiKey: String) async throws {
        createFormWebViewAndListenCalled = true
        createFormWebViewAndListenExpectation?.fulfill()
        // Call super to properly set up viewModel and viewController
        try await super.createFormWebViewAndListen(apiKey: apiKey)
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
        try await super.handleLifecycleEvent(event)
    }
}
