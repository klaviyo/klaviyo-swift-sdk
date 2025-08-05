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
    func testDispatchLifecycleEventInjection() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())

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
    func testBackgroundPersistEventInjected() async throws {
        // This test has been flaky when running on CI. It seems to have something to do with instability when
        // running a WKWebView in a CI test environment. Until we find a fix for this, we'll skip running this test on CI.
        let isRunningOnCI = Bool(ProcessInfo.processInfo.environment["GITHUB_CI"] ?? "false") ?? false
        try XCTSkipIf(isRunningOnCI, "Skipping test in Github CI environment")

        // Given
        let expectation = XCTestExpectation(description: "Background lifecycle event script is injected")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        mockLifecycleEvents.send(.backgrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('background')")
        })
    }

    @MainActor
    func testForegroundWithinSessionKeepsViewControllerAlive() async throws {
        // Given
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should not be destroyed when foregrounding within session")
        XCTAssertFalse(presentationManager.createFormAndAwaitFormEventsCalled, "Web view should not be recreated when foregrounding within session")
    }

    @MainActor
    func testForegroundWithinSessionRestoreEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Foreground lifecycle event script is injected")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('foreground')")
        })
    }

    @MainActor
    func testForegroundInNewSessionCreatesNewViewController() async throws {
        // Given
        let destroyExpectation = XCTestExpectation(description: "Web view is destroyed on new session")
        let createExpectation = XCTestExpectation(description: "Web view is created on new session")
        presentationManager.destroyWebviewExpectation = destroyExpectation
        presentationManager.createFormAndAwaitFormEventsExpectation = createExpectation

        mockApiKeyPublisher.send("test-api-key")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [destroyExpectation, createExpectation], timeout: 5.0)
        XCTAssertTrue(presentationManager.destroyWebviewCalled, "Web view should be destroyed when foregrounding in new session")
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Web view should be recreated when foregrounding in new session")
    }

    @MainActor
    func testForegroundInNewSessionPurgeEventInjected() async throws {
        // Given
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        let expectation = XCTestExpectation(description: "Foreground lifecycle event script is injected")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 second

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('foreground')")
        })
    }

    @MainActor
    func testForegroundFromExistingInstanceDoesNotCreatesNewViewController() async throws {
        // Given
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertFalse(mockManager.createFormAndAwaitFormEventsCalled, "createFormAndAwaitFormEvents should not be called when foregrounding in existing instance (such as opening the notificaiton/control center)")
    }

    @MainActor
    func testForegroundNewLaunchCreatesNewViewController() async throws {
        // Given
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        let mockManager = MockIAFPresentationManager(viewController: nil) // simulate fresh launch
        mockManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.createFormAndAwaitFormEventsCalled, "createFormAndAwaitFormEvents should be called when foregrounding on new launch/new session")
    }

    @MainActor
    func testForegroundNewLaunchRestoreEventInjected() async throws {
        // Given
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 3.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('foreground')")
        })
    }

    @MainActor
    func testIntializeApiKeyChangeCreatesNewViewController() async throws {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.initializeIAF(configuration: InAppFormsConfig())

        // When
        mockApiKeyPublisher.send("initial-key")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.createFormAndAwaitFormEventsCalled, "createFormAndAwaitFormEvents should be called when foregrounding in new session")
    }

    @MainActor
    func testDestroyWebviewAndListenersCleansUpLifecycleSubscription() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event script is not injected after destroying listener")
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())
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
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig())
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
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: -1))
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
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 0))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Form should be recreated immediately when using zero timeout duration")
    }

    @MainActor
    func testInfiniteSessionTimeoutDurationNeverResets() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Form is not recreated after session timeout")
        expectation.isInverted = true
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        // When
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: TimeInterval.infinity))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(presentationManager.createFormAndAwaitFormEventsCalled, "Form should not be recreated when using infinite timeout duration")
    }

    @MainActor
    func testValidSessionTimeoutDurationResetsAfterTimeout() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Form is recreated after session timeout")
        presentationManager.createFormAndAwaitFormEventsExpectation = expectation

        // When
        mockApiKeyPublisher.send("test-api-key")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds to allow initialization
        presentationManager.setupLifecycleEventsSubscription(configuration: InAppFormsConfig(sessionTimeoutDuration: 1))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        mockLifecycleEvents.send(.foregrounded)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(presentationManager.createFormAndAwaitFormEventsCalled, "Form should be recreated after timeout duration")
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
}
