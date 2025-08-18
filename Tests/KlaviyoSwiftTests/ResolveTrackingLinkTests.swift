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

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await store.receive(.trackingLinkDestinationResolved(destinationURL))
        await store.receive(.openDeepLink(destinationURL))
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

        // When
        await store.send(.trackingLinkReceived(trackingLinkURL))
        // Then
        await store.receive(.trackingLinkDestinationResolved(destinationURL))
        await store.receive(.openDeepLink(destinationURL))
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = URL(string: "https://email.klaviyo.com/tracking/link")!

        // Mock API failure
        environment.klaviyoAPI.send = { _, _ in
            .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled)))
        }

        // When/Then
        await store.send(.trackingLinkReceived(trackingLinkURL))

        // TODO: [CHNL-22886] validate that error is handled properly
    }

    @MainActor
    func testResolveTrackingLinkDecodingError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())

        // When/Then
        await store.send(.trackingLinkReceived(trackingLinkURL))

        // TODO: [CHNL-22886] validate that error is handled properly
    }

    @MainActor
    func testTrackingLinkDestinationResolvedTriggersOpenDeepLink() async throws {
        // Given
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))
        let store = TestStore(initialState: INITIALIZED_TEST_STATE(), reducer: KlaviyoReducer())

        let openCalled = expectation(description: "environment.openURL called with destination")
        environment.openURL = { url in
            XCTAssertEqual(url, destinationURL)
            openCalled.fulfill()
        }

        // When
        await store.send(.trackingLinkDestinationResolved(destinationURL))

        // Then the reducer should emit .openDeepLink and call environment.openURL
        await store.receive(.openDeepLink(destinationURL))
        await fulfillment(of: [openCalled], timeout: 1.0)
    }
}
