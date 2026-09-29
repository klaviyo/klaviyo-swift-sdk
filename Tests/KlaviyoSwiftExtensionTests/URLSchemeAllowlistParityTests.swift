@testable import KlaviyoSwiftExtension
import KlaviyoCore
import XCTest

/// `openUrlAllowedSchemes` is intentionally duplicated in KlaviyoCore and KlaviyoSwiftExtension
/// because the extension target cannot depend on KlaviyoCore. This test fails if the two copies
/// drift, which would let the NSE and the main app disagree on which `open_url` schemes are allowed.
final class URLSchemeAllowlistParityTests: XCTestCase {
    func testExtensionAllowlistMatchesCoreAllowlist() {
        XCTAssertEqual(
            KlaviyoSwiftExtension.openUrlAllowedSchemes,
            KlaviyoCore.openUrlAllowedSchemes,
            "openUrlAllowedSchemes copies in KlaviyoCore and KlaviyoSwiftExtension must stay in sync."
        )
    }
}
