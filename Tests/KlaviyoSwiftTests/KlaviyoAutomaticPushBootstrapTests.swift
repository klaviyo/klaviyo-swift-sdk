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
            openKey: 1
        ]))
    }
}
