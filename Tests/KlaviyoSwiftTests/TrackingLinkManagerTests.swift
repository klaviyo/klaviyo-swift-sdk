//
//  TrackingLinkManagerTests.swift
//
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class TrackingLinkManagerTests: XCTestCase {
    private let trackingLink = URL(string: "https://email.klaviyo.com/tracking/link")!
    private let profileInfo = ProfilePayload(
        email: "test@example.com",
        phoneNumber: nil,
        externalId: nil,
        anonymousId: "anon-1"
    )

    @MainActor
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
    }

    func testResolveDestinationReturnsResolvedOnSuccess() async throws {
        let destinationURL = try XCTUnwrap(URL(string: "https://example.com/destination"))
        let responseData = try XCTUnwrap("""
        {
            "original_destination": "\(destinationURL.absoluteString)"
        }
        """.data(using: .utf8))

        environment.decoder = DataDecoder(jsonDecoder: JSONDecoder())
        environment.klaviyoAPI.send = { request, _ in
            XCTAssertEqual(request.endpoint, KlaviyoEndpoint.resolveDestinationURL(
                trackingLink: self.trackingLink,
                profileInfo: self.profileInfo
            ))
            return .success(responseData)
        }

        let outcome = await TrackingLinkManager.resolveDestination(
            trackingLink: trackingLink,
            profileInfo: profileInfo
        )

        XCTAssertEqual(outcome, .resolved(destinationURL))
    }

    func testResolveDestinationReturnsFailedOnAPIError() async {
        environment.klaviyoAPI.send = { _, _ in
            .failure(.networkError(NSError(domain: "foo", code: NSURLErrorCancelled)))
        }

        let outcome = await TrackingLinkManager.resolveDestination(
            trackingLink: trackingLink,
            profileInfo: profileInfo
        )

        XCTAssertEqual(outcome, .failed)
    }

    func testResolveDestinationReturnsFailedOnDecodeError() async throws {
        let responseData = try XCTUnwrap("{}".data(using: .utf8))
        environment.decoder = DataDecoder(jsonDecoder: InvalidJSONDecoder())
        environment.klaviyoAPI.send = { _, _ in .success(responseData) }

        let outcome = await TrackingLinkManager.resolveDestination(
            trackingLink: trackingLink,
            profileInfo: profileInfo
        )

        XCTAssertEqual(outcome, .failed)
    }
}
