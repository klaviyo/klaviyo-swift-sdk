//
//  IAFPresentationManagerTeardownTests.swift
//  klaviyo-swift-sdk
//

@testable import KlaviyoForms
import KlaviyoCore
import XCTest

/// Regression guard (MAGE-834): In-App Forms teardown must NOT clobber global identity/config.
final class IAFPresentationManagerTeardownTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        environment = KlaviyoEnvironment.test()
        IdentityStore.shared.reset()
        SDKConfigStore.shared.reset()
    }

    @MainActor
    func testTeardownDoesNotClobberGlobalIdentityAndConfig() {
        let identity = ProfileData(email: "person@example.com", anonymousId: "anon-1")
        let config = KlaviyoConfig(apiKey: "company-123")
        IdentityStore.shared.update(identity)
        SDKConfigStore.shared.update(config)

        IAFPresentationManager.shared.destroyWebviewAndListeners()

        XCTAssertEqual(IdentityStore.shared.current, identity)
        XCTAssertEqual(SDKConfigStore.shared.current, config)
    }
}
