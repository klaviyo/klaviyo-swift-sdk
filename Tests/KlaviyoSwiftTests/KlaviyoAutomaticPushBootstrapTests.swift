@testable import KlaviyoAutomaticPushBootstrap
import XCTest

final class KlaviyoAutomaticPushBootstrapTests: XCTestCase {
    private let tokenKey = "klaviyo_automatic_push_token_forwarding"
    private let openKey = "klaviyo_automatic_push_open_tracking"

    func testBootstrapIsDisabledWhenBothFlagsAreAbsentOrFalse() {
        XCTAssertFalse(KlaviyoAutomaticPushBootstrapShouldInstall([:]))
        XCTAssertFalse(KlaviyoAutomaticPushBootstrapShouldInstall([
            tokenKey: false,
            openKey: false
        ]))
    }

    func testBootstrapIsEnabledForEitherIndependentFlag() {
        XCTAssertTrue(KlaviyoAutomaticPushBootstrapShouldInstall([tokenKey: true]))
        XCTAssertTrue(KlaviyoAutomaticPushBootstrapShouldInstall([openKey: true]))
        XCTAssertTrue(KlaviyoAutomaticPushBootstrapShouldInstall([
            tokenKey: true,
            openKey: true
        ]))
    }

    func testBootstrapRejectsMalformedFlagValues() {
        XCTAssertFalse(KlaviyoAutomaticPushBootstrapShouldInstall([
            tokenKey: "true",
            openKey: 2
        ]))
    }

    /// Matches Swift's `as? Bool` bridging for the same Info.plist keys
    /// (`KlaviyoSwiftEnvironment.production`): an integer-valued flag of exactly 0 or 1 must
    /// evaluate identically here and in the Swift gate, so the feature isn't enabled by one
    /// code path and skipped by the other depending on which evaluates the flag first.
    func testBootstrapAcceptsIntegerZeroOrOneMatchingSwiftBridging() {
        XCTAssertTrue(KlaviyoAutomaticPushBootstrapShouldInstall([openKey: 1]))
        XCTAssertFalse(KlaviyoAutomaticPushBootstrapShouldInstall([openKey: 0]))
    }
}
