//
//  FormLifecycleHandlerTests.swift
//  klaviyo-swift-sdk
//
//  Created by Klaviyo SDK Team on 2026-02-20.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import XCTest

final class FormLifecycleHandlerTests: XCTestCase {
    // MARK: - Properties

    var presentationManager: IAFPresentationManager!

    // MARK: - Setup & Teardown

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        presentationManager = IAFPresentationManager.shared
        presentationManager.unregisterFormLifecycleHandler()
    }

    @MainActor
    override func tearDown() async throws {
        presentationManager.unregisterFormLifecycleHandler()
        presentationManager = nil
        try await super.tearDown()
    }

    // MARK: - Registration Tests

    @MainActor
    func testRegisterHandler() {
        // Given
        var capturedEvent: FormLifecycleEvent?
        let handler: (FormLifecycleEvent) -> Void = { event in
            capturedEvent = event
        }

        // When
        presentationManager.registerFormLifecycleHandler(handler)

        // Then - verify handler works
        presentationManager.invokeLifecycleHandler(for: .formShown)
        XCTAssertEqual(capturedEvent, .formShown, "Handler should be invoked with correct event")
    }

    @MainActor
    func testUnregisterHandler() {
        // Given
        var handlerInvoked = false
        let handler: (FormLifecycleEvent) -> Void = { _ in
            handlerInvoked = true
        }
        presentationManager.registerFormLifecycleHandler(handler)

        // When
        presentationManager.unregisterFormLifecycleHandler()

        // Then - verify handler is not invoked after unregistration
        presentationManager.invokeLifecycleHandler(for: .formShown)
        XCTAssertFalse(handlerInvoked, "Handler should not be invoked after unregistration")
    }

    @MainActor
    func testRegisteringNewHandlerReplacesOld() {
        // Given
        var firstHandlerInvoked = false
        var secondHandlerInvoked = false

        let firstHandler: (FormLifecycleEvent) -> Void = { _ in
            firstHandlerInvoked = true
        }

        let secondHandler: (FormLifecycleEvent) -> Void = { _ in
            secondHandlerInvoked = true
        }

        // When
        presentationManager.registerFormLifecycleHandler(firstHandler)
        presentationManager.registerFormLifecycleHandler(secondHandler)
        presentationManager.invokeLifecycleHandler(for: .formShown)

        // Then
        XCTAssertFalse(firstHandlerInvoked, "First handler should be replaced")
        XCTAssertTrue(secondHandlerInvoked, "Second handler should be invoked")
    }

    // MARK: - Event Tests

    @MainActor
    func testHandlerCalledForFormShown() {
        // Given
        let expectation = expectation(description: "Handler called for formShown")
        var receivedEvent: FormLifecycleEvent?

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formShown)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent, .formShown, "Handler should receive formShown event")
    }

    @MainActor
    func testHandlerCalledForFormDismissed() {
        // Given
        let expectation = expectation(description: "Handler called for formDismissed")
        var receivedEvent: FormLifecycleEvent?

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formDismissed)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent, .formDismissed, "Handler should receive formDismissed event")
    }

    @MainActor
    func testHandlerCalledForFormCTAClicked() {
        // Given
        let expectation = expectation(description: "Handler called for formCTAClicked")
        var receivedEvent: FormLifecycleEvent?

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formCTAClicked)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent, .formCTAClicked, "Handler should receive formCTAClicked event")
    }

    @MainActor
    func testMultipleEventsInSequence() {
        // Given
        let expectation = expectation(description: "Handler called for all events")
        expectation.expectedFulfillmentCount = 3
        var receivedEvents: [FormLifecycleEvent] = []

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvents.append(event)
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formShown)
        presentationManager.invokeLifecycleHandler(for: .formCTAClicked)
        presentationManager.invokeLifecycleHandler(for: .formDismissed)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvents.count, 3, "Handler should be called three times")
        XCTAssertEqual(receivedEvents[0], .formShown, "First event should be formShown")
        XCTAssertEqual(receivedEvents[1], .formCTAClicked, "Second event should be formCTAClicked")
        XCTAssertEqual(receivedEvents[2], .formDismissed, "Third event should be formDismissed")
    }

    // MARK: - Edge Case Tests

    @MainActor
    func testInvokeWithoutHandler() {
        // Given - No handler registered

        // When/Then - Should not crash
        presentationManager.invokeLifecycleHandler(for: .formShown)
        presentationManager.invokeLifecycleHandler(for: .formDismissed)
        presentationManager.invokeLifecycleHandler(for: .formCTAClicked)

        // Test passes if no crash occurs
        XCTAssertTrue(true, "Invoking without handler should not crash")
    }

    @MainActor
    func testHandlerCalledOnMainThread() {
        // Given
        let expectation = expectation(description: "Handler called on main thread")
        var isMainThread = false

        presentationManager.registerFormLifecycleHandler { _ in
            isMainThread = Thread.isMainThread
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formShown)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(isMainThread, "Handler should be called on main thread")
    }

    // MARK: - Public API Tests

    @MainActor
    func testPublicAPIRegistration() {
        // Given
        let expectation = expectation(description: "Handler called via public API")
        var receivedEvent: FormLifecycleEvent?

        // When
        KlaviyoSDK().registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        presentationManager.invokeLifecycleHandler(for: .formShown)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent, .formShown, "Public API should register handler correctly")
    }

    @MainActor
    func testPublicAPIUnregistration() {
        // Given
        var handlerInvoked = false
        KlaviyoSDK().registerFormLifecycleHandler { _ in
            handlerInvoked = true
        }

        // When
        KlaviyoSDK().unregisterFormLifecycleHandler()

        // Then
        presentationManager.invokeLifecycleHandler(for: .formShown)
        XCTAssertFalse(handlerInvoked, "Handler should not be invoked after unregistration")
    }

    @MainActor
    func testPublicAPIChaining() {
        // Given/When
        let sdk = KlaviyoSDK()
            .registerFormLifecycleHandler { _ in }

        // Then
        XCTAssertNotNil(sdk, "registerFormLifecycleHandler should return KlaviyoSDK instance")

        // When
        let unregisteredSDK = sdk.unregisterFormLifecycleHandler()

        // Then
        XCTAssertNotNil(unregisteredSDK, "unregisterFormLifecycleHandler should return KlaviyoSDK instance")
    }

    // MARK: - Event Enum Tests

    func testFormLifecycleEventRawValues() {
        XCTAssertEqual(FormLifecycleEvent.formShown.rawValue, "form_shown")
        XCTAssertEqual(FormLifecycleEvent.formDismissed.rawValue, "form_dismissed")
        XCTAssertEqual(FormLifecycleEvent.formCTAClicked.rawValue, "form_cta_clicked")
    }

    func testFormLifecycleEventEquality() {
        XCTAssertEqual(FormLifecycleEvent.formShown, FormLifecycleEvent.formShown)
        XCTAssertEqual(FormLifecycleEvent.formDismissed, FormLifecycleEvent.formDismissed)
        XCTAssertEqual(FormLifecycleEvent.formCTAClicked, FormLifecycleEvent.formCTAClicked)

        XCTAssertNotEqual(FormLifecycleEvent.formShown, FormLifecycleEvent.formDismissed)
        XCTAssertNotEqual(FormLifecycleEvent.formShown, FormLifecycleEvent.formCTAClicked)
        XCTAssertNotEqual(FormLifecycleEvent.formDismissed, FormLifecycleEvent.formCTAClicked)
    }
}
