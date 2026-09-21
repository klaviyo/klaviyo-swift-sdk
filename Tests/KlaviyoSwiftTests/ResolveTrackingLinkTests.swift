//
//  ResolveTrackingLinkTests.swift
//  klaviyo-swift-sdk
//
//  Created by Claude on 8/4/25.
//

@testable import KlaviyoCore
@_spi(KlaviyoPrivate) @testable import KlaviyoSwift
import Combine
import XCTest

final class ResolveTrackingLinkTests: XCTestCase {
    /// Live in-memory backing for the QueueStore under `TEST_API_KEY`, so the failure path can
    /// assert the enqueued tracking-link request.
    private var readQueue: () -> [KlaviyoRequest] = { [] }

    @MainActor
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        resetCanonicalCoreStores()
        LifecycleState.shared.reset()
        UnattributedBuffer.shared.reset()
        klaviyoSwiftEnvironment = KlaviyoSwiftEnvironment.test()
        DeepLinkManager.resetToProduction()
        readQueue = seedTestQueueStore()
    }

    @MainActor
    override func tearDown() async throws {
        DeepLinkManager.resetToProduction()
        LifecycleState.shared.reset()
        try await super.tearDown()
    }

    /// Seeds the canonical stores to the `INITIALIZED_TEST_STATE` shape (apiKey + anon, initialized).
    @MainActor
    @discardableResult
    private func seedInitialized() -> String {
        let anonymousId = environment.uuid().uuidString
        SDKConfigStore.shared.update(KlaviyoConfig(apiKey: TEST_API_KEY))
        IdentityStore.shared.update(ProfileData(anonymousId: anonymousId))
        LifecycleState.shared.beginInitializing()
        LifecycleState.shared.completeInitialization()
        return anonymousId
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithSuccess() async throws {
        // Given
        let anonymousId = seedInitialized()
        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))

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
                    email: nil,
                    phoneNumber: nil,
                    externalId: nil,
                    anonymousId: anonymousId
                )
            ))
            return .success(responseData)
        }

        // On success the destination routes straight to DeepLinkManager.
        let opened = expectation(description: "openDeepLink invoked with destination")
        DeepLinkManager.openDeepLinkSpy = { url in
            XCTAssertEqual(url, destinationURL)
            opened.fulfill()
        }

        // When
        KlaviyoOrchestration.trackingLinkReceived(trackingLinkURL)
        // Then
        await fulfillment(of: [opened], timeout: 1.0)
    }

    @MainActor
    func testResolveTrackingLinkDestinationWhenNotInitialized() async throws {
        // Given (pre-init: identity has an anon, but lifecycle stays uninitialized)
        let anonymousId = environment.uuid().uuidString
        IdentityStore.shared.update(ProfileData(anonymousId: anonymousId))
        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))

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
                    email: nil,
                    phoneNumber: nil,
                    externalId: nil,
                    anonymousId: anonymousId
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
        KlaviyoOrchestration.trackingLinkReceived(trackingLinkURL)
        // Then
        await fulfillment(of: [opened], timeout: 1.0)
    }

    @MainActor
    func testResolveTrackingLinkDestinationWithError() async throws {
        // Given
        seedInitialized()
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = { clickTime }

        let trackingLinkURL = URL(string: "https://email.klaviyo.com/tracking/link")!

        // Mock API failure
        environment.klaviyoAPI.send = { _, _ in
            .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled)))
        }

        // When
        KlaviyoOrchestration.trackingLinkReceived(trackingLinkURL)

        // Then: a failed resolution enqueues a click-log request.
        let anonymousId = try XCTUnwrap(IdentityStore.shared.current.anonymousId)
        let expected = KlaviyoRequest(
            endpoint: .logTrackingLinkClicked(
                trackingLink: trackingLinkURL,
                clickTime: clickTime,
                profileInfo: ProfilePayload(
                    email: IdentityStore.shared.current.email,
                    phoneNumber: IdentityStore.shared.current.phoneNumber,
                    externalId: IdentityStore.shared.current.externalId,
                    anonymousId: anonymousId
                )
            )
        )
        try await waitForQueue { self.readQueue() == [expected] }
        XCTAssertEqual(
            readQueue(), [expected],
            "failed tracking-link resolution enqueues a log request"
        )
    }

    @MainActor
    func testPreInitTrackingLinkResolutionFailedBuffers() async throws {
        // Pre-init (no apiKey in SDKConfigStore): a failed tracking-link resolution must park its
        // click-log in the durable buffer instead of dropping it.
        IdentityStore.shared.update(ProfileData(anonymousId: environment.uuid().uuidString))
        let clickTime = environment.date()
        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        KlaviyoOrchestration.trackingLinkResolutionFailed(
            trackingLink: trackingLinkURL, clickTime: clickTime
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
        seedInitialized()
        let clickTime = Date(timeIntervalSince1970: 1_735_707_600)
        environment.date = { clickTime }

        let trackingLinkURL = try XCTUnwrap(URL(string: "https://email.klaviyo.com/tracking/link"))

        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())

        // When
        KlaviyoOrchestration.trackingLinkReceived(trackingLinkURL)

        // Then: a decode failure is treated as a resolution failure → enqueues a click-log request.
        let anonymousId = try XCTUnwrap(IdentityStore.shared.current.anonymousId)
        let expected = KlaviyoRequest(
            endpoint: .logTrackingLinkClicked(
                trackingLink: trackingLinkURL,
                clickTime: clickTime,
                profileInfo: ProfilePayload(
                    email: IdentityStore.shared.current.email,
                    phoneNumber: IdentityStore.shared.current.phoneNumber,
                    externalId: IdentityStore.shared.current.externalId,
                    anonymousId: anonymousId
                )
            )
        )
        try await waitForQueue { self.readQueue() == [expected] }
        XCTAssertEqual(
            readQueue(), [expected],
            "failed tracking-link resolution enqueues a log request"
        )
    }

    /// Polls `condition` (the async resolution `Task` enqueues off the caller) until true or timeout.
    private func waitForQueue(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
