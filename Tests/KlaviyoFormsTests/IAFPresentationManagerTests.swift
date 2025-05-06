//
//  IAFPresentationManagerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/3/25.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
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

    var presentationManager: IAFPresentationManager!
    fileprivate var mockViewController: MockKlaviyoWebViewController!
    fileprivate var mockViewModel: MockIAFWebViewModel!
    var mockLifecycleEvents: PassthroughSubject<LifeCycleEvents, Never>!
    var mockApiKeyPublisher: PassthroughSubject<String?, Never>!
    var cancellables: Set<AnyCancellable> = []

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "lastBackgrounded")
        mockViewModel = MockIAFWebViewModel(url: URL(string: "https://example.com")!)
        mockViewController = MockKlaviyoWebViewController(viewModel: mockViewModel)
        mockLifecycleEvents = PassthroughSubject<LifeCycleEvents, Never>()
        mockApiKeyPublisher = PassthroughSubject<String?, Never>()

        // Initialize test environment
        environment = KlaviyoEnvironment.test()

        // Setup mock environment with test lifecycle events
        let testLifecycleEvents = AppLifeCycleEvents(lifeCycleEvents: {
            self.mockLifecycleEvents.eraseToAnyPublisher()
        })
        environment.appLifeCycle = testLifecycleEvents

        // Setup mock state management with API key publisher
        let initialState = KlaviyoState(queue: [])
        let testStore = Store(initialState: initialState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        presentationManager = IAFPresentationManager(viewController: mockViewController)
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
        presentationManager.setupLifecycleEvents()

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
    func testSetupLifecycleEvents() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle events are handled by IAFPresentationManager")

        // Track JavaScript evaluations to verify event handling
        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        presentationManager.setupLifecycleEvents()
    }

    @MainActor
    func testBackgroundEventLogsTimestamp() async throws {
        // Given
        presentationManager.setupLifecycleEvents()

        // When
        mockLifecycleEvents.send(.backgrounded)

        // Then
        // Wait a short time for the event to be processed
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let timestamp = UserDefaults.standard.object(forKey: "lastBackgrounded") as? Date
        XCTAssertNotNil(timestamp, "Background timestamp should be stored in UserDefaults")
        XCTAssertLessThanOrEqual(timestamp?.timeIntervalSinceNow ?? 0, 0, "Timestamp should be in the past")
    }

    @MainActor
    func testBackgroundPersistEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents()

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
        UserDefaults.standard.set(Date().addingTimeInterval(-1.0), forKey: "lastBackgrounded")
        presentationManager.setupLifecycleEvents()
        let firstViewController = presentationManager.viewController

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        XCTAssertEqual(firstViewController, presentationManager.viewController, "Web view should not be destroyed and recreated when foregrounding within session")
    }

    @MainActor
    func testForegroundWithinSessionRestoreEventInjected() async throws {
        // Given
        UserDefaults.standard.set(Date().addingTimeInterval(-1.0), forKey: "lastBackgrounded")
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents()

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
        UserDefaults.standard.set(Date().addingTimeInterval(-10.0), forKey: "lastBackgrounded")

        // Setup initial web view
        let firstViewController = presentationManager.viewController
        XCTAssertNotNil(firstViewController, "Initial web view should be created")

        // Setup lifecycle events
        presentationManager.setupLifecycleEvents()

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        // Wait for async operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertNotEqual(firstViewController, presentationManager.viewController, "Web view should be destroyed and recreated when foregrounding in new session")
    }

    @MainActor
    func testForegroundInNewSessionPurgeEventInjected() async throws {
        // Given
        UserDefaults.standard.set(Date().addingTimeInterval(-10.0), forKey: "lastBackgrounded")
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents()

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
        let firstViewController = presentationManager.viewController
        XCTAssertNotNil(firstViewController, "Initial web view should be created")

        // Setup lifecycle events
        presentationManager.setupLifecycleEvents()

        // When
        mockLifecycleEvents.send(.foregrounded)

        // Then
        XCTAssertNotEqual(firstViewController, presentationManager.viewController, "Web view should be destroyed and recreated when foregrounding in new session")
    }

    @MainActor
    func testForegroundNewLaunchRestoreEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents()

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
    func testApiKeyChangePurgeEventInjected() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Lifecycle event script is injected")
        presentationManager.setupLifecycleEvents()

        var evaluatedScripts: [String] = []
        mockViewController.evaluateJavaScriptCallback = { script in
            evaluatedScripts.append(script)
            if script.contains("dispatchLifecycleEvent") {
                expectation.fulfill()
            }
            return true
        }

        // When
        mockApiKeyPublisher.send("initial-key")
        mockApiKeyPublisher.send("new-key")

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(evaluatedScripts.contains { script in
            script.contains("dispatchLifecycleEvent('foreground', 'purge')")
        })
    }

    @MainActor
    func testApiKeyChangeCreatesNewViewController() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Web view is recreated")
        presentationManager.setupLifecycleEvents()

        // Setup initial web view
        let firstViewController = presentationManager.viewController
        XCTAssertNotNil(firstViewController, "Initial web view should be created")

        // When
        mockApiKeyPublisher.send("initial-key")
        mockApiKeyPublisher.send("new-key")

        // Then
        // Wait for async operations to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertNotEqual(firstViewController, presentationManager.viewController, "Web view should be destroyed and recreated when API key changes")
        XCTAssertTrue(mockViewController.dismissCalled)
    }
}

// MARK: - Mock Classes

private final class MockKlaviyoWebViewController: KlaviyoWebViewController {
    var dismissCalled = false
    var evaluateJavaScriptCallback: ((String) -> Any)?

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCalled = true
        completion?()
    }

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
    func handleViewTransition() {}
}
