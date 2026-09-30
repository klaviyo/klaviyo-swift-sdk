//
//  IAFWebViewModelTests.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/6/25.
//

@testable import KlaviyoForms
@testable import KlaviyoSwift
import KlaviyoCore
import WebKit
import XCTest

// Test-specific subclass that overrides navigation policy to allow all navigation
// This is required to get these unit tests to pass
private class TestKlaviyoWebViewController: KlaviyoWebViewController {
    override func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        .allow
    }
}

// Captures inbound commands dispatched through the Core `EventDispatcher` lane.
private final class SpyDispatcher: EventDispatching {
    private(set) var received: [InboundCommand] = []
    func dispatch(_ command: InboundCommand) { received.append(command) }
}

final class IAFWebViewModelTests: XCTestCase {
    // MARK: - Properties

    var viewModel: IAFWebViewModel!

    // MARK: - Setup

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Reset environment to clean state to avoid state persistence from other tests
        environment = KlaviyoEnvironment.test()
        environment.sdkName = { "swift" }
        environment.sdkVersion = { "0.0.1" }
        // Override CDN URL to return the expected production URL for tests
        environment.cdnURL = {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "static.klaviyo.com"
            return components
        }

        seedCoreStores()

        // Reset klaviyoSwiftEnvironment state to clean test state with expected API key
        let testState = KlaviyoState(
            apiKey: "abc123",
            queue: [],
            requestsInFlight: [],
            initalizationState: .initialized
        )
        let testStore = Store(initialState: testState, reducer: KlaviyoReducer())
        klaviyoSwiftEnvironment.statePublisher = {
            testStore.state.eraseToAnyPublisher()
        }

        // Read the seeded config/identity from the canonical Core stores
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        let profileData = IdentityStore.shared.current

        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: profileData)
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - SDK Attribute Tests

    @MainActor
    func testInjectSdkNameAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let sdkNameScript = viewModel.findScript(containing: ["data-sdk-name", "swift"])

        // Then
        XCTAssertNotNil(sdkNameScript, "SDK name script should be injected")
    }

    @MainActor
    func testInjectSdkVersionAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let sdkVersionScript = viewModel.findScript(containing: ["data-sdk-version", "0.0.1"])

        // Then
        XCTAssertNotNil(sdkVersionScript, "SDK version script should be injected")
    }

    // MARK: - Environment Tests

    @MainActor
    func testInjectFormsDataEnvironmentAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: "data-forms-data-environment")

        // Then
        XCTAssertNil(environmentScript, "Forms data environment script should not be injected when not set")
    }

    @MainActor
    func testInjectFormsDataEnvironmentSetToWeb() async throws {
        // Given
        environment.formsDataEnvironment = { .web }

        // Create a new viewModel with the updated environment
        let fileUrl = try XCTUnwrap(Bundle.module.url(forResource: "IAFUnitTest", withExtension: "html"))
        let apiKey = try XCTUnwrap(SDKConfigStore.shared.current.apiKey)
        viewModel = IAFWebViewModel(url: fileUrl, apiKey: apiKey, profileData: nil)

        // When
        viewModel.initializeLoadScripts()
        let environmentScript = viewModel.findScript(containing: ["data-forms-data-environment", "web"])

        // Then
        XCTAssertNotNil(environmentScript, "Forms data environment script should be injected when set to web")
    }

    // MARK: - Handshake Tests

    @MainActor
    func testInjectHandshakeAttribute() async throws {
        // When
        viewModel.initializeLoadScripts()
        let handshakeScript = viewModel.findScript(containing: "data-native-bridge-handshake")

        // Then
        XCTAssertNotNil(handshakeScript, "Handshake script should be injected")

        // Extract the handshake string from the script source
        let scriptSource = handshakeScript?.source ?? ""
        let components = scriptSource.components(separatedBy: "'")
        guard components.count >= 2 else {
            XCTFail("Could not find handshake data in script")
            return
        }
        let handshakeString = components[components.count - 2]

        // Verify handshake data
        struct TestableHandshakeData: Codable, Equatable {
            var type: String
            var version: Int
        }

        let expectedHandshakeString =
            """
            [{"type":"formWillAppear","version":2},{"type":"formDisappeared","version":1},{"type":"trackProfileEvent","version":2},{"type":"trackAggregateEvent","version":1},{"type":"openDeepLink","version":3},{"type":"abort","version":1},{"type":"lifecycleEvent","version":1},{"type":"profileEvent","version":1},{"type":"profileMutation","version":1}]
            """
        let expectedData = try XCTUnwrap(expectedHandshakeString.data(using: .utf8))
        let expectedHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: expectedData)

        let actualData = try XCTUnwrap(handshakeString.data(using: .utf8))
        let actualHandshakeData = try JSONDecoder().decode([TestableHandshakeData].self, from: actualData)
        XCTAssertEqual(actualHandshakeData, expectedHandshakeData)
    }

    // MARK: - Klaviyo JS Tests

    @MainActor
    func testInjectKlaviyoJsScript() async throws {
        // When
        viewModel.initializeLoadScripts()
        let klaviyoJsScript = viewModel.findScript(containing: ["klaviyoJS", "static.klaviyo.com/onsite/js/klaviyo.js"])

        // Then
        XCTAssertNotNil(klaviyoJsScript, "Klaviyo JS script should be injected")
        XCTAssertTrue(klaviyoJsScript?.source.contains("company_id=abc123") ?? false, "Script should include company ID")
        XCTAssertTrue(klaviyoJsScript?.source.contains("env=in-app") ?? false, "Script should include environment")
    }

    // MARK: - Event Handling Tests

    @MainActor
    func testFormWillAppearYieldsPresentLifecycleEvent() async throws {
        // When - simulate a form will appear script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {
                "formId": "test123",
                "formName": "Test Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("present", from: viewModel.formLifecycleStream) { event in
            if case .present = event { return true }
            return false
        }
    }

    @MainActor
    func testFormDisappearedYieldsDismissLifecycleEvent() async throws {
        // When - simulate a form disappeared script message with formId and formName
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {
                "formId": "dismiss123",
                "formName": "Dismiss Form"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("dismiss", from: viewModel.formLifecycleStream) { event in
            if case .dismiss = event { return true }
            return false
        }
    }

    @MainActor
    func testFormWillAppearYieldsPresentEvenWithMissingMetadata() async throws {
        // When - simulate a formWillAppear with empty data (no formId/formName)
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formWillAppear",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .present should still be yielded
        await assertLifecycleEvent("present", from: viewModel.formLifecycleStream) { event in
            if case .present = event { return true }
            return false
        }
    }

    @MainActor
    func testFormDisappearedYieldsDismissEvenWithMissingMetadata() async throws {
        // When - simulate a formDisappeared with empty data
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "formDisappeared",
              "data": {}
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then - .dismiss should still be yielded
        await assertLifecycleEvent("dismiss", from: viewModel.formLifecycleStream) { event in
            if case .dismiss = event { return true }
            return false
        }
    }

    @MainActor
    func testAbortEventYieldsAbortLifecycleEvent() async throws {
        // Given
        let abortReason = "test abort reason"

        // When - simulate an abort script message
        let scriptMessage = MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: """
            {
              "type": "abort",
              "data": {
                "reason": "\(abortReason)"
              }
            }
            """
        )

        viewModel.handleScriptMessage(scriptMessage)

        // Then
        await assertLifecycleEvent("abort", from: viewModel.formLifecycleStream) { event in
            if case .abort = event { return true }
            return false
        }
    }

    // MARK: - External URL Tests (openDeepLink with openExternally: true)

    private func makeOpenExternalUrlMessage(
        url: String? = "https://example.com",
        formId: String? = "form123",
        formName: String? = "Newsletter",
        buttonLabel: String? = "Learn More"
    ) -> MockWKScriptMessage {
        // External web URLs ride the openDeepLink message with openExternally: true;
        // the URL is sent in the platform-split `ios`/`android` keys.
        var data: [String: String] = [:]
        data["ios"] = url
        data["android"] = url
        data["formId"] = formId
        data["formName"] = formName
        data["buttonLabel"] = buttonLabel
        let dataJson = data.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let dataBody = dataJson.isEmpty ? "\"openExternally\": true" : "\(dataJson), \"openExternally\": true"
        return MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: "{ \"type\": \"openDeepLink\", \"data\": { \(dataBody) } }"
        )
    }

    @MainActor
    func testHandleOpenExternalUrlFiresLifecycleEvent() async throws {
        // Given
        var receivedEvent: FormLifecycleEvent?
        IAFPresentationManager.shared.registerFormLifecycleHandler { event in
            receivedEvent = event
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // A spurious dispatch through EventDispatcher would mean the deep-link path ran
        // instead. IAFWebViewModel's deep-link branch calls EventDispatcher.shared.dispatch
        // synchronously (no Task), so checking immediately after is reliable — no race.
        let spyDispatcher = SpyDispatcher()
        EventDispatcher.shared.register(spyDispatcher)
        defer { EventDispatcher.shared.reset() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage())

        // Then — the handler path is synchronous, so assert immediately.
        // External URL clicks surface through the same formCtaClicked event as deep links.
        guard case let .formCtaClicked(formId, formName, buttonLabel, url) = receivedEvent else {
            XCTFail("Expected formCtaClicked, got \(String(describing: receivedEvent))")
            return
        }
        XCTAssertEqual(formId, "form123")
        XCTAssertEqual(formName, "Newsletter")
        XCTAssertEqual(buttonLabel, "Learn More")
        XCTAssertEqual(url, URL(string: "https://example.com"))
        XCTAssertTrue(
            spyDispatcher.received.isEmpty,
            "openExternally: true must not route through EventDispatcher's deep-link path"
        )
    }

    @MainActor
    func testHandleOpenExternalUrlWithoutFormMetadataSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(formId: nil, formName: nil))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Lifecycle event should not fire without form metadata")
    }

    @MainActor
    func testHandleOpenExternalUrlWithMissingUrlSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(url: nil))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Lifecycle event should not fire with nil URL")
    }

    @MainActor
    func testHandleOpenExternalUrlWithDisallowedSchemeSkipsLifecycleEvent() async throws {
        // Given
        var lifecycleEventFired = false
        IAFPresentationManager.shared.registerFormLifecycleHandler { _ in
            lifecycleEventFired = true
        }
        defer { IAFPresentationManager.shared.unregisterFormLifecycleHandler() }

        // When
        viewModel.handleScriptMessage(makeOpenExternalUrlMessage(url: "javascript://alert(1)"))

        // Then
        XCTAssertFalse(lifecycleEventFired, "Blocked scheme should skip navigation and lifecycle event")
    }

    // MARK: - trackProfileEvent Tests

    /// Sends a `trackProfileEvent` bridge message carrying `data`, and returns every command
    /// that reached the Core `EventDispatcher`.
    @MainActor
    private func sendTrackProfileEvent(data: String) -> [InboundCommand] {
        let spyDispatcher = SpyDispatcher()
        EventDispatcher.shared.register(spyDispatcher)
        defer { EventDispatcher.shared.reset() }

        viewModel.handleScriptMessage(MockWKScriptMessage(
            name: "KlaviyoNativeBridge",
            body: "{ \"type\": \"trackProfileEvent\", \"data\": \(data) }"
        ))

        return spyDispatcher.received
    }

    /// The `Event` dispatched for a `trackProfileEvent` message, or `nil` if the message
    /// produced anything other than exactly one `.createEvent` command.
    @MainActor
    private func createdEvent(from data: String) -> Event? {
        let received = sendTrackProfileEvent(data: data)
        guard received.count == 1, case let .createEvent(event) = received[0] else { return nil }
        return event
    }

    @MainActor
    func testTrackProfileEventFlattensNestedProperties() throws {
        // Given/When - the payload onsite sends: a metric plus a nested property object
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Form completed by profile",
          "properties": {
            "form_id": "1",
            "form_version_id": 2,
            "channel_type": "IN_APP",
            "foo": "bar"
          }
        }
        """))

        // Then - the nested object becomes the event's properties, flat and unwrapped
        XCTAssertEqual(event.metric.name, .customEvent("Form completed by profile"))
        XCTAssertEqual(event.properties["form_id"] as? String, "1")
        XCTAssertEqual(event.properties["form_version_id"] as? Int, 2)
        XCTAssertEqual(event.properties["channel_type"] as? String, "IN_APP")
        XCTAssertEqual(event.properties["foo"] as? String, "bar")
        XCTAssertEqual(event.properties.count, 4)
        XCTAssertNil(event.properties["metric"], "envelope keys must not become event properties")
        XCTAssertNil(event.properties["properties"], "properties must be flattened, not nested")
    }

    @MainActor
    func testTrackProfileEventIgnoresHoistedSiblings() throws {
        // Given/When - the nested object plus the same keys repeated at the top level
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Form completed by profile",
          "properties": {
            "form_id": "1",
            "form_version_id": 2,
            "channel_type": "IN_APP"
          },
          "form_id": "1",
          "form_version_id": 2,
          "channel_type": "IN_APP"
        }
        """))

        // Then - only the nested object is read; the top-level duplicates change nothing
        XCTAssertEqual(event.properties["form_id"] as? String, "1")
        XCTAssertEqual(event.properties["form_version_id"] as? Int, 2)
        XCTAssertEqual(event.properties["channel_type"] as? String, "IN_APP")
        XCTAssertEqual(event.properties.count, 3)
    }

    @MainActor
    func testTrackProfileEventHonorsValueAndUniqueId() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Placed Order",
          "properties": { "form_id": "1" },
          "value": 9.99,
          "unique_id": "form-event-1"
        }
        """))

        // Then - both ride the top level of the envelope, not the property bag
        XCTAssertEqual(event.value, 9.99)
        XCTAssertEqual(event.uniqueId, "form-event-1")
        XCTAssertEqual(event.properties.count, 1)
        XCTAssertNil(event.properties["value"])
        XCTAssertNil(event.properties["unique_id"])
    }

    @MainActor
    func testTrackProfileEventHonorsValueCurrency() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Placed Order",
          "properties": { "form_id": "1" },
          "value": 9.99,
          "value_currency": "CAD"
        }
        """))

        // Then - the currency rides the top level of the envelope, not the property bag
        XCTAssertEqual(event.value, 9.99)
        XCTAssertEqual(event.valueCurrency, "CAD")
        XCTAssertEqual(event.properties.count, 1)
        XCTAssertNil(event.properties["value_currency"])
    }

    @MainActor
    func testTrackProfileEventOmitsValueCurrencyWhenAbsent() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        { "metric": "Placed Order", "properties": {}, "value": 9.99 }
        """))

        // Then
        XCTAssertNil(event.valueCurrency)
    }

    @MainActor
    func testTrackProfileEventAcceptsIntegerValue() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        { "metric": "Placed Order", "properties": {}, "value": 10 }
        """))

        // Then
        XCTAssertEqual(event.value, 10)
    }

    @MainActor
    func testTrackProfileEventIgnoresNonNumericValue() throws {
        // Given/When - `value` is a string, a shape the v2 contract (`value?: number`) does not allow
        let event = try XCTUnwrap(createdEvent(from: """
        { "metric": "Placed Order", "properties": {}, "value": "9.99" }
        """))

        // Then - the event still dispatches, without a value
        XCTAssertNil(event.value)
    }

    @MainActor
    func testTrackProfileEventDefaultsValueAndUniqueIdWhenAbsent() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Form completed by profile",
          "properties": { "form_id": "1" }
        }
        """))

        // Then - no value, and a generated unique id (fixed by the test environment)
        XCTAssertNil(event.value)
        XCTAssertEqual(event.uniqueId, "00000000-0000-0000-0000-000000000001")
    }

    @MainActor
    func testTrackProfileEventWithFlatPayloadDropsTopLevelKeys() throws {
        // Given/When - a flat payload, with no nested property object
        let event = try XCTUnwrap(createdEvent(from: """
        {
          "metric": "Viewed Product",
          "foo": "bar"
        }
        """))

        // Then - the metric is still tracked, but top-level keys are not event properties
        XCTAssertEqual(event.metric.name, .customEvent("Viewed Product"))
        XCTAssertTrue(event.properties.isEmpty)
    }

    @MainActor
    func testTrackProfileEventWithNonObjectPropertiesStillDispatches() throws {
        // Given/When
        let event = try XCTUnwrap(createdEvent(from: """
        { "metric": "Form completed by profile", "properties": "nope" }
        """))

        // Then
        XCTAssertEqual(event.metric.name, .customEvent("Form completed by profile"))
        XCTAssertTrue(event.properties.isEmpty)
    }

    @MainActor
    func testTrackProfileEventWithoutUsableMetricDispatchesNothing() {
        // Given/When/Then - a metric that is missing, non-string, or empty produces no event
        XCTAssertTrue(sendTrackProfileEvent(data: """
        { "properties": { "form_id": "1" } }
        """).isEmpty, "a payload with no metric must not produce an event")

        XCTAssertTrue(sendTrackProfileEvent(data: """
        { "metric": 42, "properties": { "form_id": "1" } }
        """).isEmpty, "a non-string metric must not produce an event")

        XCTAssertTrue(sendTrackProfileEvent(data: """
        { "metric": "", "properties": { "form_id": "1" } }
        """).isEmpty, "an empty metric must not produce an event")
    }
}

extension IAFWebViewModel {
    @MainActor
    fileprivate func findScript(containing text: String) -> WKUserScript? {
        loadScripts?.first { script in
            script.source.contains(text)
        }
    }

    @MainActor
    fileprivate func findScript(containing texts: [String]) -> WKUserScript? {
        loadScripts?.first { script in
            texts.allSatisfy { text in
                script.source.contains(text)
            }
        }
    }
}
