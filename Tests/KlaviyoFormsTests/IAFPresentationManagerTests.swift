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
        super.tearDown()
    }

    // MARK: - tests

    @MainActor
    func testDispatchLifecycleEventInjection() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        try await presentationManager.handleLifecycleEvent("test", "test")

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('test', 'test')")
        })
    }

    @MainActor
    func testBackgroundPersistEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Background lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())

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
            script.contains("dispatchLifecycleEvent('background', 'persist')")
        })
    }

    @MainActor
    func testForegroundWithinSessionKeepsViewControllerAlive() async throws {
        // Given
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        XCTAssertFalse(presentationManager.destroyWebviewCalled, "Web view should not be destroyed when foregrounding within session")
        XCTAssertFalse(presentationManager.constructWebviewCalled, "Web view should not be recreated when foregrounding within session")
    }

    @MainActor
    func testForegroundWithinSessionRestoreEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Foreground lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration(sessionTimeoutDuration: 2))
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
            script.contains("dispatchLifecycleEvent('foreground', 'restore')")
        })
    }

    @MainActor
    func testForegroundInNewSessionCreatesNewViewController() async throws {
        // Given
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration(sessionTimeoutDuration: 2))
        mockLifecycleEvents.send(.backgrounded)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        XCTAssertTrue(presentationManager.destroyWebviewCalled, "Web view should be destroyed when foregrounding in new session")
        XCTAssertTrue(presentationManager.constructWebviewCalled, "Web view should be recreated when foregrounding in new session")
    }

    @MainActor
    func testForegroundInNewSessionPurgeEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Foreground lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration(sessionTimeoutDuration: 2))
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
            script.contains("dispatchLifecycleEvent('foreground', 'purge')")
        })
    }

    @MainActor
    func testForegroundNewLaunchCreatesNewViewController() async throws {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.setupLifecycleEvents(configuration: IAFConfiguration())

        // When
        mockLifecycleEvents.send(.foregrounded)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.constructWebviewCalled, "constructWebview should be called when foregrounding in new session")
    }

    @MainActor
    func testForegroundNewLaunchRestoreEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())

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
            script.contains("dispatchLifecycleEvent('foreground', 'restore')")
        })
    }

    @MainActor
    func testIntializeApiKeyChangeCreatesNewViewController() async throws {
        // Given
        let mockManager = MockIAFPresentationManager(viewController: mockViewController)
        mockManager.setupLifecycleEvents(configuration: IAFConfiguration())

        // When
        mockApiKeyPublisher.send("initial-key")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(mockManager.constructWebviewCalled, "constructWebview should be called when foregrounding in new session")
    }

    @MainActor
    func testSubsequentApiKeyChangesPurgeEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") && script.contains("purge") {
                expectation.fulfill()
            }
            return true
        }

        // When
        // First send initializes the API key
        mockApiKeyPublisher.send("ABC123")
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        mockApiKeyPublisher.send("ABC321")

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('foreground', 'purge')")
        })
    }

    @MainActor
    func testDestroyWebviewAndListenersCleansUpLifecycleSubscription() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Event script is not injected after destroying listener")
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())
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
        presentationManager.setupLifecycleEvents(configuration: IAFConfiguration())
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
    var constructWebviewCalled = false
    var destroyWebviewCalled = false
    var formEventTask: Task<Void, Never>?

    override func constructWebview(assetSource: String? = nil) {
        constructWebviewCalled = true
        super.constructWebview(assetSource: assetSource)
    }

    override func destroyWebView() {
        destroyWebviewCalled = true
        super.destroyWebView()
    }

    override func dismissForm() {
        destroyWebviewCalled = true
        super.destroyWebView()
    }
}
