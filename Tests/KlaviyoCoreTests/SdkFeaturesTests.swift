//
//  SdkFeaturesTests.swift
//  KlaviyoCoreTests
//
//  Created by Glenn Brannelly on 7/7/26.
//

@testable import KlaviyoCore
import XCTest

final class SdkFeaturesTests: XCTestCase {
    /// Master on, escape hatch present and off: both fields reported, forwarding on (typical opt-in).
    func testHeaderValueTrackingOnForwardingOn() {
        let features = SdkFeatures(autoPushTrackingEnabled: true, autoTokenForwardingDisabled: false)
        XCTAssertTrue(features.autoPushTracking)
        XCTAssertEqual(features.autoPushTokenForwarding, true)
        XCTAssertEqual(features.headerValue, "auto_push_tracking=1; auto_push_token_forwarding=1;")
    }

    /// Master on, escape hatch present and set: proxy stays active but forwarding collapses to off.
    func testHeaderValueTrackingOnForwardingDisabled() {
        let features = SdkFeatures(autoPushTrackingEnabled: true, autoTokenForwardingDisabled: true)
        XCTAssertTrue(features.autoPushTracking)
        XCTAssertEqual(features.autoPushTokenForwarding, false)
        XCTAssertEqual(features.headerValue, "auto_push_tracking=1; auto_push_token_forwarding=0;")
    }

    /// Escape-hatch key absent: the token-forwarding field is omitted entirely (not marked as used),
    /// rather than reported with a default value.
    func testHeaderOmitsForwardingWhenEscapeHatchKeyAbsent() {
        let features = SdkFeatures(autoPushTrackingEnabled: true, autoTokenForwardingDisabled: nil)
        XCTAssertTrue(features.autoPushTracking)
        XCTAssertNil(features.autoPushTokenForwarding)
        XCTAssertEqual(features.headerValue, "auto_push_tracking=1;")
    }

    /// Master off, escape-hatch key absent: only the master field is reported.
    func testHeaderTrackingOffForwardingKeyAbsent() {
        let features = SdkFeatures(autoPushTrackingEnabled: false, autoTokenForwardingDisabled: nil)
        XCTAssertFalse(features.autoPushTracking)
        XCTAssertNil(features.autoPushTokenForwarding)
        XCTAssertEqual(features.headerValue, "auto_push_tracking=0;")
    }

    /// The escape hatch is a no-op when the master is off; forwarding can never be on without tracking.
    func testForwardingIsOffWheneverTrackingIsOff() {
        let features = SdkFeatures(autoPushTrackingEnabled: false, autoTokenForwardingDisabled: false)
        XCTAssertEqual(features.autoPushTokenForwarding, false)
        XCTAssertEqual(features.headerValue, "auto_push_tracking=0; auto_push_token_forwarding=0;")
    }
}
