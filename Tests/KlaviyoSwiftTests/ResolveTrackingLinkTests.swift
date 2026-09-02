//
//  ResolveTrackingLinkTests.swift
//  klaviyo-swift-sdk
//
//  Created by Claude on 8/4/25.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import Combine
import XCTest

final class ResolveTrackingLinkTests: XCTestCase {
    /// Live in-memory backing for the QueueStore under `TEST_API_KEY` (the key used by
    /// `INITIALIZED_TEST_STATE`), so the failure path can assert the enqueued tracking-link request.
    private var readQueue: () -> [KlaviyoRequest] = { [] }

    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        UnattributedBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        DeepLinkManager.resetToProduction()
        readQueue = seedTestQueueStore(apiKey: TEST_API_KEY)
    }

    @MainActor
    override func tearDown() async throws {
        DeepLinkManager.resetToProduction()
        try await super.tearDown()
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithSuccess() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))

        // Mock successful API response
        let responseJSON = """
        {
            "original_destination": "\(destinationURL.absoluteString)"
        }
        """
        let responseData = try XCTUnwrap(responseJSON.data(using: .utf8))

        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())

        environment.klaviyoAPI.send = { request, _ in
            XCTAssertEqual(request.endpoint, KlaviyoEndpoint.resolveDestinationURL(
                trackingLink: trackingLinkURL,
                profileInfo: ProfilePayload(
                    email: initialState.email,
                    phoneNumber: initialState.phoneNumber,
                    externalId: initialState.externalId,
                    anonymousId: initialState.anonymousId ?? ""
                )
            ))
            return .success(responseData)
        }

        // On success the reducer routes the destination straight to DeepLinkManager.
        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await fulfillment(of: [opened], timeout: 1.0)
        await store.finish()
    }

    @MainActor
    func testResolveTrackingLinkDestinationWhenNotInitialized() async throws {
        // Given
        var initialState = INITIALIZED_TEST_STATE()
        initialState.initalizationState = .uninitialized
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))

        // Mock successful API response
        let responseJSON = """
        {
            "original_destination": "\(destinationURL.absoluteString)"
        }
        """
        let responseData = try XCTUnwrap(responseJSON.data(using: .utf8))

        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())

        environment.klaviyoAPI.send = { request, _ in
            XCTAssertEqual(request.endpoint, KlaviyoEndpoint.resolveDestinationURL(
                trackingLink: trackingLinkURL,
                profileInfo: ProfilePayload(
                    email: initialState.email,
                    phoneNumber: initialState.phoneNumber,
                    externalId: initialState.externalId,
                    anonymousId: initialState.anonymousId ?? ""
                )
            ))
            return .success(responseData)
        }

        // Tracking-link resolution is not init-gated, so it still resolves and navigates.
        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await fulfillment(of: [opened], timeout: 1.0)
        await store.finish()
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = {
            clickTime
        }

        let trackingLinkURL = URL(string: "https://email.klaviyo.com/tracking/link")!

        // Mock API failure
        environment.klaviyoAPI.send = { _, _ in
            .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled)))
        }

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))

        // Then
        await store.receive(
            .trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime)
        )
        let request = KlaviyoRequest(
            endpoint: .logTrackingLinkClicked(
                trackingLink: trackingLinkURL,
                clickTime: clickTime,
                profileInfo: ProfilePayload(
                    email: initialState.email,
                    phoneNumber: initialState.phoneNumber,
                    externalId: initialState.externalId,
                    anonymousId: initialState.anonymousId ?? ""
                )
            )
        )
        XCTAssertEqual(
            readQueue(), [request],
            "failed tracking-link resolution enqueues a log request"
        )
    }

    @MainActor
    func testPreInitTrackingLinkResolutionFailedBuffers() async throws {
        // Pre-init (no apiKey in SDKConfigStore): a failed tracking-link resolution must park its
        // click-log in the durable buffer instead of dropping it via the apiKey-gated
        // `state.enqueueRequest` (MAGE-1136).
        let store = TestStore(
            initialState: KlaviyoState(requestsInFlight: []), reducer: KlaviyoReducer()
        )
        store.exhaustivity = .off
        let clickTime = environment.date()
        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        await store.send(
            .trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime)
        )

        let (buffered, _) = UnattributedBuffer.shared.drainSnapshot()
        XCTAssertEqual(buffered.count, 1, "pre-init tracking-link click is buffered, not dropped")
        guard case let .trackingLinkClick(link, time, _) = buffered.first else {
            return XCTFail("expected a buffered .trackingLinkClick")
        }
        XCTAssertEqual(link, trackingLinkURL)
        XCTAssertEqual(time, clickTime)
    }

    @MainActor
    func testResolveTrackingLinkDecodingError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        store.exhaustivity = .off
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = {
            clickTime
        }

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))

        // Then
        await store.receive(
            .trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime)
        )
        let request = KlaviyoRequest(
            endpoint: .logTrackingLinkClicked(
                trackingLink: trackingLinkURL,
                clickTime: clickTime,
                profileInfo: ProfilePayload(
                    email: initialState.email,
                    phoneNumber: initialState.phoneNumber,
                    externalId: initialState.externalId,
                    anonymousId: initialState.anonymousId ?? ""
                )
            )
        )
        XCTAssertEqual(
            readQueue(), [request],
            "failed tracking-link resolution enqueues a log request"
        )
    }
}
