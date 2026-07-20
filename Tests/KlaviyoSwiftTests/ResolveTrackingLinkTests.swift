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
    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        DeepLinkManager.resetToProduction()
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

        // Observe the deep-link open that trackingLinkDestinationResolved triggers.
        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await store.receive(.trackingLinkDestinationResolved(destinationURL))
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

        // Observe the deep-link open that trackingLinkDestinationResolved triggers.
        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await store.receive(.trackingLinkDestinationResolved(destinationURL))
        await fulfillment(of: [opened], timeout: 1.0)
        await store.finish()
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
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
        await store.receive(.trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime)) {
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

            $0.queue = [request]
        }
    }

    @MainActor
    func testResolveTrackingLinkDecodingError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = {
            clickTime
        }

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))

        // Then
        await store.receive(.trackingLinkResolutionFailed(trackingLink: trackingLinkURL, clickTime: clickTime)) {
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

            $0.queue = [request]
        }
    }

    @MainActor
    func testTrackingLinkDestinationResolvedTriggersOpenDeepLink() async throws {
        // Given
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))
        let store = TestStore(initialState: INITIALIZED_TEST_STATE(), reducer: KlaviyoReducer())

        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        await store.send(.trackingLinkDestinationResolved(destinationURL))

        // Then the reducer should route the destination through DeepLinkManager.
        await fulfillment(of: [opened], timeout: 1.0)
        await store.finish()
    }
}
