//
//  IAFConfigurationTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 5/7/25.
//

@testable import KlaviyoForms
import XCTest

final class IAFConfigurationTests: XCTestCase {
    @MainActor
    func testConfigurationInPresentationManager() async {
        // Test with default configuration
        let manager = IAFPresentationManager.shared
        XCTAssertEqual(manager.configuration.sessionTimeoutDuration, 3600, "Presentation manager should use default configuration")

        // Test with custom configuration
        let customTimeout: TimeInterval = 1800
        let customConfig = IAFConfiguration(sessionTimeoutDuration: customTimeout)
        manager.setupLifecycleEvents(configuration: customConfig)
        XCTAssertEqual(manager.configuration.sessionTimeoutDuration, customTimeout, "Presentation manager should update to custom configuration")
    }

    @MainActor
    func testConfigurationPersistence() async {
        let manager = IAFPresentationManager.shared

        // Set initial configuration
        let initialTimeout: TimeInterval = 1800
        let initialConfig = IAFConfiguration(sessionTimeoutDuration: initialTimeout)
        manager.setupLifecycleEvents(configuration: initialConfig)
        XCTAssertEqual(manager.configuration.sessionTimeoutDuration, initialTimeout)

        // Call setupLifecycleEvents again without configuration
        manager.setupLifecycleEvents()
        XCTAssertEqual(manager.configuration.sessionTimeoutDuration, initialTimeout, "Configuration should persist when no new configuration is provided")
    }
}
