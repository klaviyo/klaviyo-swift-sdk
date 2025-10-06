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
        let ciVariables = [
            "TEST_RUNNER_GITHUB_CI",
            "GITHUB_ACTIONS",
            "GITHUB_CI",
            "CI"
        ]
        for variable in ciVariables {
            if env[variable] == "true" {
                print("CI detected via environment variable: \(variable)")
                return true
            }
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

        // this unwrapping prevents a crash that sometimes happens because mockLifecycleEvents is nil
        if let lifecycleEvents = mockLifecycleEvents {
            environment.appLifeCycle = AppLifeCycleEvents(lifeCycleEvents: {
                lifecycleEvents.eraseToAnyPublisher()
            })
        }

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

        presentationManager = MockIAFPresentationManager(viewController: mockViewController, viewModel: mockViewModel)
        mockApiKeyPublisher.send("setup-key") // initialize SDK
        try await Task.sleep(nanoseconds: 1_000_000_000) // wait for initialization to be completed
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
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        try XCTSkipIf(isRunningInCI(), "Skipping test in Github CI environment")

        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        try XCTSkipIf(isRunningInCI(), "Skipping test in Github CI environment")

        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        try XCTSkipIf(isRunningInCI(), "Skipping test in Github CI environment")

        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

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
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

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
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        // When
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: -1))
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered
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
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        try XCTSkipIf(isRunningInCI(), "Skipping test in Github CI environment")

        // Given
        presentationManager.initializeIAF(configuration: InAppFormsConfig(sessionTimeoutDuration: .infinity))
        mockApiKeyPublisher.send("test-api-key") // force view controller to be triggered

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
    func testHandleProfileEventWithEmoji() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event with emoji is handled successfully")
        var evaluatedScripts: [String] = []
        var caughtError: Error?

        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            print("📝 Evaluated script: \(script)")
            if script.contains("dispatchProfileEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When - test with emoji in event name
        let testEvent = Event(name: .customEvent("Push Opened 🎉"), properties: ["title": "Test Push"])

        do {
            try await presentationManager.handleProfileEventCreated(testEvent)
        } catch {
            caughtError = error
        }

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNil(caughtError, "Should not throw error with emoji in event name")

        let scriptWithEmoji = evaluatedScripts.first { script in
            script.contains("dispatchProfileEvent") && script.contains("🎉")
        }
        XCTAssertNotNil(scriptWithEmoji, "Should find script with emoji")

        if let script = scriptWithEmoji {
            print("✅ Script with emoji: \(script)")
            // Verify the script is syntactically correct JavaScript
            XCTAssertTrue(script.contains("'Push Opened 🎉'"), "Event name with emoji should be properly formatted")
        }
    }

    @MainActor
    func testHandleProfileEventWithSpecialCharacters() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event with special characters is handled")
        var evaluatedScripts: [String] = []
        var caughtError: Error?

        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            print("📝 Evaluated script: \(script)")
            if script.contains("dispatchProfileEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When - test with single quote in event name
        let testEvent = Event(name: .customEvent("User's Action"), properties: [:])

        do {
            try await presentationManager.handleProfileEventCreated(testEvent)
        } catch {
            caughtError = error
        }

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)

        if let error = caughtError {
            print("❌ Error caught: \(error)")
        }

        let scriptWithQuote = evaluatedScripts.first { script in
            script.contains("dispatchProfileEvent")
        }

        if let script = scriptWithQuote {
            print("📄 Generated script: \(script)")
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

    // MARK: - Event Buffering Tests

    @MainActor
    func testPendingEventsArrayStartsEmpty() {
        XCTAssertEqual(presentationManager.pendingProfileEvents.count, 0)
        XCTAssertFalse(presentationManager.isFormsDataLoaded)
    }

    @MainActor
    func testIsFormsDataLoadedFlagStartsFalse() {
        XCTAssertFalse(presentationManager.isFormsDataLoaded)
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

    let formLifecycleStream: AsyncStream<IAFLifecycleEvent>
    private let formLifecycleContinuation: AsyncStream<IAFLifecycleEvent>.Continuation

    init(url: URL) {
        self.url = url
        let (stream, continuation) = AsyncStream.makeStream(of: IAFLifecycleEvent.self)
        formLifecycleStream = stream
        formLifecycleContinuation = continuation
    }

    func establishHandshake(timeout: TimeInterval) async throws {
        // Mock implementation - immediately succeeds
    }

    func waitForFormsDataLoaded(timeout: TimeInterval) async throws {
        // Mock implementation - immediately succeeds
    }

    func handleNavigationEvent(_ event: KlaviyoForms.WKNavigationEvent) {}
    func handleScriptMessage(_ message: WKScriptMessage) {}
}

private final class MockProfileObserver: JSBridgeObserver {
    let stream: AsyncStream<Event>
    let continuation: AsyncStream<Event>.Continuation

    var eventsStream: AsyncStream<Event> { stream }

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    func startObserving() {
        // Mock - do nothing
    }

    func stopObserving() {
        continuation.finish()
    }

    func simulateEvent(_ event: Event) {
        continuation.yield(event)
    }
}

private final class MockIAFPresentationManager: IAFPresentationManager {
    var createFormAndAwaitFormEventsCalled = false
    var destroyWebviewCalled = false
    var formEventTask: Task<Void, Never>?
    var destroyWebviewExpectation: XCTestExpectation?
    var createFormAndAwaitFormEventsExpectation: XCTestExpectation?
    var handledEvents: [String] = []
    var mockProfileObserver: MockProfileObserver?

    override func createFormAndAwaitFormEvents(apiKey: String) async throws {
        createFormAndAwaitFormEventsCalled = true
        createFormAndAwaitFormEventsExpectation?.fulfill()
        // Skip creating new viewController/viewModel since mocks are already set
        // Just start listening for form events
        listenForFormEvents()
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
