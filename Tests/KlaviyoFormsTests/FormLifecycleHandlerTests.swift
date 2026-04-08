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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))
        if case .formShown = capturedEvent {
            // pass
        } else {
            XCTFail("Handler should be invoked with formShown event")
        }
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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))
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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))

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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))

        // Then
        wait(for: [expectation], timeout: 1.0)
        if case let .formShown(formId, formName) = receivedEvent {
            XCTAssertEqual(formId, "", "formId should be empty string when no form context available")
            XCTAssertEqual(formName, "", "formName should be empty string when no form context available")
        } else {
            XCTFail("Handler should receive formShown event, got \(String(describing: receivedEvent))")
        }
    }

    @MainActor
    func testFormContextFlowsThroughEvent() {
        // Given
        let expectation = expectation(description: "Handler called with form context in event")
        var receivedEvent: FormLifecycleEvent?

        presentationManager.registerFormLifecycleHandler { event in
            if case .formShown = event {
                receivedEvent = event
                expectation.fulfill()
            }
        }

        // When - invoke formShown with explicit context
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "form123", formName: "Test Form"))

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent?.formId, "form123", "formId should match")
        XCTAssertEqual(receivedEvent?.formName, "Test Form", "formName should match")
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
        presentationManager.invokeLifecycleHandler(for: .formDismissed(formId: "", formName: ""))

        // Then
        wait(for: [expectation], timeout: 1.0)
        if case .formDismissed = receivedEvent {
            // pass
        } else {
            XCTFail("Handler should receive formDismissed event, got \(String(describing: receivedEvent))")
        }
    }

    @MainActor
    func testHandlerCalledForFormCtaClicked() {
        // Given
        let expectation = expectation(description: "Handler called for formCtaClicked")
        var receivedEvent: FormLifecycleEvent?

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formCtaClicked(
            formId: "",
            formName: "",
            buttonLabel: "",
            deepLinkUrl: URL(string: "myapp://test")!
        ))

        // Then
        wait(for: [expectation], timeout: 1.0)
        if case .formCtaClicked = receivedEvent {
            // pass
        } else {
            XCTFail("Handler should receive formCtaClicked event, got \(String(describing: receivedEvent))")
        }
    }

    @MainActor
    func testCtaEventCarriesButtonLabelAndUrl() {
        // Given
        let expectation = expectation(description: "formCtaClicked carries buttonLabel and deepLinkUrl")
        var receivedEvent: FormLifecycleEvent?
        let deepLink = URL(string: "myapp://checkout")!

        presentationManager.registerFormLifecycleHandler { event in
            receivedEvent = event
            expectation.fulfill()
        }

        // When
        presentationManager.invokeLifecycleHandler(for: .formCtaClicked(
            formId: "form123",
            formName: "Promo Form",
            buttonLabel: "Shop Now",
            deepLinkUrl: deepLink
        ))

        // Then
        wait(for: [expectation], timeout: 1.0)
        guard case let .formCtaClicked(formId, formName, buttonLabel, deepLinkUrl) = receivedEvent else {
            XCTFail("Expected formCtaClicked, got \(String(describing: receivedEvent))")
            return
        }
        XCTAssertEqual(formId, "form123")
        XCTAssertEqual(formName, "Promo Form")
        XCTAssertEqual(buttonLabel, "Shop Now")
        XCTAssertEqual(deepLinkUrl, deepLink)
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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))
        presentationManager.invokeLifecycleHandler(
            for: .formCtaClicked(formId: "", formName: "", buttonLabel: "", deepLinkUrl: URL(string: "myapp://test")!)
        )
        presentationManager.invokeLifecycleHandler(for: .formDismissed(formId: "", formName: ""))

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvents.count, 3, "Handler should be called three times")
        if case .formShown = receivedEvents[0] { } else {
            XCTFail("First event should be formShown")
        }
        if case .formCtaClicked = receivedEvents[1] { } else {
            XCTFail("Second event should be formCtaClicked")
        }
        if case .formDismissed = receivedEvents[2] { } else {
            XCTFail("Third event should be formDismissed")
        }
    }

    // MARK: - Edge Case Tests

    @MainActor
    func testInvokeWithoutHandler() {
        // Given - No handler registered

        // When/Then - Should not crash
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))
        presentationManager.invokeLifecycleHandler(for: .formDismissed(formId: "", formName: ""))
        presentationManager.invokeLifecycleHandler(
            for: .formCtaClicked(formId: "", formName: "", buttonLabel: "", deepLinkUrl: URL(string: "myapp://test")!)
        )

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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))

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

        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))

        // Then
        wait(for: [expectation], timeout: 1.0)
        if case .formShown = receivedEvent {
            // pass
        } else {
            XCTFail("Public API should register handler correctly, got \(String(describing: receivedEvent))")
        }
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
        presentationManager.invokeLifecycleHandler(for: .formShown(formId: "", formName: ""))
        XCTAssertFalse(handlerInvoked, "Handler should not be invoked after unregistration")
    }

    @MainActor
    func testPublicAPIChaining() {
        // Given/When
        let klaviyoSDK = KlaviyoSDK()
            .registerFormLifecycleHandler { _ in }

        // Then
        XCTAssertNotNil(klaviyoSDK, "registerFormLifecycleHandler should return KlaviyoSDK instance")

        // When
        let unregisteredSDK = klaviyoSDK.unregisterFormLifecycleHandler()

        // Then
        XCTAssertNotNil(unregisteredSDK, "unregisterFormLifecycleHandler should return KlaviyoSDK instance")
    }

    // MARK: - FormLifecycleEvent Computed Property Tests

    func testFormIdComputedProperty() {
        XCTAssertEqual(FormLifecycleEvent.formShown(formId: "abc", formName: "").formId, "abc")
        XCTAssertEqual(FormLifecycleEvent.formDismissed(formId: "def", formName: "").formId, "def")
        let ctaEvent = FormLifecycleEvent.formCtaClicked(
            formId: "ghi", formName: "", buttonLabel: "", deepLinkUrl: URL(string: "myapp://test")!
        )
        XCTAssertEqual(ctaEvent.formId, "ghi")
        XCTAssertEqual(FormLifecycleEvent.formShown(formId: "", formName: "").formId, "")
    }

    func testFormNameComputedProperty() {
        XCTAssertEqual(FormLifecycleEvent.formShown(formId: "", formName: "Form A").formName, "Form A")
        XCTAssertEqual(FormLifecycleEvent.formDismissed(formId: "", formName: "Form B").formName, "Form B")
        let ctaEventC = FormLifecycleEvent.formCtaClicked(
            formId: "", formName: "Form C", buttonLabel: "", deepLinkUrl: URL(string: "myapp://test")!
        )
        XCTAssertEqual(ctaEventC.formName, "Form C")
        XCTAssertEqual(FormLifecycleEvent.formShown(formId: "", formName: "").formName, "")
    }

    func testFormLifecycleEventEquality() {
        XCTAssertEqual(
            FormLifecycleEvent.formShown(formId: "abc", formName: "Test"),
            FormLifecycleEvent.formShown(formId: "abc", formName: "Test")
        )
        XCTAssertEqual(
            FormLifecycleEvent.formDismissed(formId: "", formName: ""),
            FormLifecycleEvent.formDismissed(formId: "", formName: "")
        )
        let ctaBuy = FormLifecycleEvent.formCtaClicked(
            formId: "x", formName: "y", buttonLabel: "Buy", deepLinkUrl: URL(string: "myapp://test")!
        )
        XCTAssertEqual(ctaBuy, ctaBuy)
        XCTAssertNotEqual(
            FormLifecycleEvent.formShown(formId: "abc", formName: ""),
            FormLifecycleEvent.formShown(formId: "xyz", formName: "")
        )
        XCTAssertNotEqual(
            FormLifecycleEvent.formShown(formId: "", formName: ""),
            FormLifecycleEvent.formDismissed(formId: "", formName: "")
        )
    }

    func testEventNameProperty() {
        XCTAssertEqual(FormLifecycleEvent.formShown(formId: "", formName: "").eventName, "formShown")
        XCTAssertEqual(
            FormLifecycleEvent.formDismissed(formId: "", formName: "").eventName, "formDismissed"
        )
        let ctaForEventName = FormLifecycleEvent.formCtaClicked(
            formId: "", formName: "", buttonLabel: "", deepLinkUrl: URL(string: "myapp://test")!
        )
        XCTAssertEqual(ctaForEventName.eventName, "formCtaClicked")
    }
}
