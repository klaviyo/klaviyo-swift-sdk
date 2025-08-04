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

        // When/Then
        await store.send(.resolveTrackingLinkDestination(from: trackingLinkURL))

        // TODO: Validate that
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
        await store.send(.resolveTrackingLinkDestination(from: trackingLinkURL))

        // TODO: validate that error is handled properly
    }

    @MainActor
    func testResolveTrackingLinkDestinationWhenNotInitialized() async throws {
        // Given
        var initialState = INITIALIZED_TEST_STATE()
        initialState.initalizationState = .uninitialized
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = URL(string: "https://email.klaviyo.com/tracking/link")!

        // When/Then - Should do nothing when not initialized
        await store.send(.resolveTrackingLinkDestination(from: trackingLinkURL))

        // No state changes or API calls should happen
    }

    @MainActor
    func testResolveTrackingLinkDecodingError() async throws {
        // Given
        let initialState = INITIALIZED_TEST_STATE()
        let store = TestStore(initialState: initialState, reducer: KlaviyoReducer())

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())

        // When/Then
        await store.send(.resolveTrackingLinkDestination(from: trackingLinkURL))

        // TODO: validate that error is handled properly
    }
}
