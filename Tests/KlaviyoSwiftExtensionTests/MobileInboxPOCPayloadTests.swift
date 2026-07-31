//
//  MobileInboxPOCPayloadTests.swift
//

@testable import KlaviyoSwiftExtension
import Foundation
import XCTest

final class MobileInboxPOCPayloadTests: XCTestCase {
    func testTransmissionIDReadsKlaviyoMetadataTransmissionID() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": [
                    "tm": "01KV8CN3SH8N7MM5ZYNX40QCFH"
                ]
            ]
        ]

        XCTAssertEqual(
            MobileInboxPOC.transmissionID(from: userInfo),
            "01KV8CN3SH8N7MM5ZYNX40QCFH"
        )
    }

    func testTransmissionIDDoesNotReadTransmissionIDOutsideKlaviyoMetadata() {
        let userInfo: [AnyHashable: Any] = [
            "body": ["tm": "not-a-klaviyo-delivery-identifier"]
        ]

        XCTAssertNil(MobileInboxPOC.transmissionID(from: userInfo))
    }

    func testPayloadTimestampReadsKlaviyoMetadataTimestamp() {
        let userInfo: [AnyHashable: Any] = [
            "body": [
                "_k": ["t": 1_718_500_000]
            ]
        ]

        XCTAssertEqual(
            MobileInboxPOC.payloadTimestamp(from: userInfo),
            Date(timeIntervalSince1970: 1_718_500_000)
        )
    }
}
