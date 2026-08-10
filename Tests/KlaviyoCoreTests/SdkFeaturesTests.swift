//
//  SdkFeaturesTests.swift
//  KlaviyoCoreTests
//
//  Created by Glenn Brannelly on 7/7/26.
//

@testable import KlaviyoCore
import XCTest

final class SdkFeaturesTests: XCTestCase {
    func testInfoPlistBooleanOnlyAcceptsBooleanValues() {
        XCTAssertEqual(SdkFeatures.infoPlistBoolean(from: NSNumber(value: true)), true)
        XCTAssertEqual(SdkFeatures.infoPlistBoolean(from: NSNumber(value: false)), false)
        XCTAssertNil(SdkFeatures.infoPlistBoolean(from: NSNumber(value: 1)))
        XCTAssertNil(SdkFeatures.infoPlistBoolean(from: "true"))
        XCTAssertNil(SdkFeatures.infoPlistBoolean(from: nil))
    }

    /// Both keys present and on: both fields reported, forwarding on (typical full opt-in).
    func testHeaderValueTrackingOnForwardingOn() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwarding: true)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertEqual(features[.autoPushTokenForwarding], true)
        XCTAssertEqual(
            features.headerValue(for: .pushTokenRegistration),
            "auto_push_tracking=1; auto_push_token_forwarding=1;"
        )
    }

    /// Both keys present, forwarding off: tracking reported on, forwarding reported off.
    func testHeaderValueTrackingOnForwardingOff() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwarding: false)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertEqual(features[.autoPushTokenForwarding], false)
        XCTAssertEqual(
            features.headerValue(for: .pushTokenRegistration),
            "auto_push_tracking=1; auto_push_token_forwarding=0;"
        )
    }

    /// Forwarding key absent: the token-forwarding field is omitted entirely.
    func testHeaderOmitsForwardingWhenForwardingKeyAbsent() {
        let features = SdkFeatures(autoPushTracking: true, autoTokenForwarding: nil)
        XCTAssertEqual(features[.autoPushTracking], true)
        XCTAssertNil(features[.autoPushTokenForwarding])
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_tracking=1;")
    }

    /// Tracking key absent, forwarding present and on: the tracking field is omitted, and forwarding
    /// reports enabled independently — now a valid configuration.
    func testHeaderOmitsTrackingWhenTrackingKeyAbsent() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwarding: true)
        XCTAssertNil(features[.autoPushTracking])
        XCTAssertEqual(features[.autoPushTokenForwarding], true)
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_token_forwarding=1;")
    }

    /// Forwarding present and off without the tracking key: only the forwarding field is emitted,
    /// reporting disabled.
    func testHeaderForForwardingOffWithoutTracking() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwarding: false)
        XCTAssertNil(features[.autoPushTracking])
        XCTAssertEqual(features[.autoPushTokenForwarding], false)
        XCTAssertEqual(features.headerValue(for: .pushTokenRegistration), "auto_push_token_forwarding=0;")
    }

    /// Neither key present: nothing to report; the header value is nil so callers omit the header.
    func testHeaderValueNilWhenNoKeysPresent() {
        let features = SdkFeatures(autoPushTracking: nil, autoTokenForwarding: nil)
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
