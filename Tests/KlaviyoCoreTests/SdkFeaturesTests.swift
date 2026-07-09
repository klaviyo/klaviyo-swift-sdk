//
//  SdkFeaturesTests.swift
//  KlaviyoCoreTests
//
//  Created by Glenn Brannelly on 7/7/26.
//

@testable import KlaviyoCore
import XCTest

final class SdkFeaturesTests: XCTestCase {
    /// Both keys present, escape hatch off: both fields reported, forwarding on (typical opt-in).
    func testHeaderValueTrackingOnForwardingOn() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwardingDisabled: false)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertEqual(features[.autoPushTokenForwarding], true)
        XCTAssertEqual(
            features.headerValue(for: .pushTokenRegistration),
            "auto_push_tracking=1; auto_push_token_forwarding=1;"
        )
    }

    /// Both keys present, escape hatch set: proxy stays active but forwarding collapses to off.
    func testHeaderValueTrackingOnForwardingDisabled() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwardingDisabled: true)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertEqual(features[.autoPushTokenForwarding], false)
        XCTAssertEqual(
            features.headerValue(for: .pushTokenRegistration),
            "auto_push_tracking=1; auto_push_token_forwarding=0;"
        )
    }

    /// Escape-hatch key absent: the token-forwarding field is omitted entirely.
    func testHeaderOmitsForwardingWhenEscapeHatchKeyAbsent() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwardingDisabled: nil)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertNil(features[.autoPushTokenForwarding])
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_tracking=1;")
    }

    /// Master key absent, escape hatch present and off: the tracking field is omitted, and forwarding
    /// reports enabled independent of the master flag.
    func testHeaderOmitsTrackingWhenPrimaryKeyAbsent() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwardingDisabled: false)
        XCTAssertNil(features[.autoPushTracking])
        XCTAssertEqual(features[.autoPushTokenForwarding], true)
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_token_forwarding=1;")
    }

    /// Escape hatch set to disable without the master key (nonsensical but captured as a usage
    /// signal): only the forwarding field is emitted, reporting disabled.
    func testHeaderForEscapeHatchWithoutPrimaryFlag() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwardingDisabled: true)
        XCTAssertNil(features[.autoPushTracking])
        XCTAssertEqual(features[.autoPushTokenForwarding], false)
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_token_forwarding=0;")
    }

    /// Neither key present: nothing to report; the header value is nil so callers omit the header.
    func testHeaderValueNilWhenNoKeysPresent() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwardingDisabled: nil)
        XCTAssertNil(features[.autoPushTracking])
        XCTAssertNil(features[.autoPushTokenForwarding])
        XCTAssertNil(features.headerValue(for: .pushTokenRegistration))
    }

    /// Serialization follows the catalog's declaration order regardless of construction order,
    /// keeping the header field ordering deterministic.
    func testHeaderValueOrderingIsDeterministic() {
        let features = SdkFeatures(values: [
            .autoPushTokenForwarding: false,
            .autoPushTracking: true
        ])
        XCTAssertEqual(
            features.headerValue(for: .pushTokenRegistration),
            "auto_push_tracking=1; auto_push_token_forwarding=0;"
        )
    }

    /// Every feature in the catalog must belong to a scope; serializing a full snapshot for each
    /// scope collectively covers all features, so none can silently go unreported.
    func testEveryFeatureIsSerializedInExactlyOneScope() {
        let allOn = SdkFeatures(values: .init(
            uniqueKeysWithValues: SdkFeatureKey.allCases.map { ($0, true) }
        ))
        let serialized = SdkFeatureScope.allCases
            .compactMap { allOn.headerValue(for: $0) }
            .joined()
        for featureKey in SdkFeatureKey.allCases {
            XCTAssertEqual(
                serialized.components(separatedBy: "\(featureKey.rawValue)=").count - 1, 1,
                "\(featureKey.rawValue) should be serialized in exactly one scope"
            )
        }
    }
}
