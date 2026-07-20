//
//  TrackingLinkDestinationResponseTests.swift
//  klaviyo-swift-sdk
//
//  Created by Claude on 8/4/25.
//

@testable import KlaviyoCore
@testable import KlaviyoSwift
import XCTest

final class TrackingLinkDestinationResponseTests: XCTestCase {
    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
    }

    func testDecodingValidResponse() throws {
        // Given
        let json = """
        {
            "original_destination": "https://example.com/destination"
        }
        """
        let jsonData = try XCTUnwrap(json.data(using: .utf8))

        // When
        let response = try JSONDecoder().decode(TrackingLinkDestinationResponse.self, from: jsonData)

        // Then
        XCTAssertEqual(response.destinationLink.absoluteString, "https://example.com/destination")
    }

    func testDecodingInvalidURL() throws {
        // Given
        let json = """
        {
            "original_destination": ""
        }
        """
        let jsonData = json.data(using: .utf8)!

        // When/Then
        XCTAssertThrowsError(try JSONDecoder().decode(TrackingLinkDestinationResponse.self, from: jsonData)) { error in
            guard let decodingError = error as? DecodingError else {
                XCTFail("Expected DecodingError")
                return
            }

            switch decodingError {
            case .dataCorrupted:
                // This is the expected error type
                break
            default:
                XCTFail("Expected .dataCorrupted error")
            }
        }
    }

    func testDecodingMissingField() throws {
        // Given
        let json = "{}"
        let jsonData = json.data(using: .utf8)!

        // When/Then
        XCTAssertThrowsError(try JSONDecoder().decode(TrackingLinkDestinationResponse.self, from: jsonData)) { error in
            guard let decodingError = error as? DecodingError else {
                XCTFail("Expected DecodingError")
                return
            }

            switch decodingError {
            case .keyNotFound:
                // This is the expected error type
                break
            default:
                XCTFail("Expected .keyNotFound error")
            }
        }
    }
}
