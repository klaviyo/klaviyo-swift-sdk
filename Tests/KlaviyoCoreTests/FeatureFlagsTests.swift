@testable import KlaviyoCore
import XCTest

final class FeatureFlagsTests: XCTestCase {
    override func tearDown() {
        featureFlags = .production
        super.tearDown()
    }

    func testProductionDefaultsAllFalse() {
        let flags = FeatureFlags.production
        XCTAssertFalse(flags.enablePreInitDiskCapture)
        XCTAssertFalse(flags.enableCompanySwitchReset)
    }

    func testGlobalIsMutableForInjection() {
        featureFlags.enableCompanySwitchReset = true
        XCTAssertTrue(featureFlags.enableCompanySwitchReset)
    }
}
