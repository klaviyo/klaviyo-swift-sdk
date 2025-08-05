//
//  KlaviyoSDK+Forms.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/20/25.
//

import Foundation
import KlaviyoSwift

extension KlaviyoSDK {
    /// Registers app to receive and display In-App Forms from Klaviyo.
    ///
    /// This will load forms data and establish ongoing listeners to present a form to the user
    /// whenever a form is triggered by an event or condition according to the targeting and behavior
    /// settings configured for forms in your Klaviyo account.
    ///
    /// - Parameter configuration: Configuration options for In-App Forms, including session timeout duration.
    ///   Defaults to a 1-hour session timeout.
    ///
    /// - Note: a public API key is required, so ``KlaviyoSDK().initialize(with:)`` must be called first. If the API key changes, the session will be re-initialized automatically with the new key.
    @MainActor
    public func registerForInAppForms(configuration: InAppFormsConfig = InAppFormsConfig()) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.initializeIAF(configuration: configuration)
            }
        }
    }

    /// Unregisters app from receiving In-App Forms and cleans up resources associated with In-App Forms (e.g. web view resources, subscriptions, state)
    @MainActor
    public func unregisterFromInAppForms() {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.destroyWebviewAndListeners()
            }
        }
    }

    /// Registers app to receive and display In-App Forms from Klaviyo with a custom asset source.
    ///
    /// This method is for internal use only and should not be used in production applications.
    /// It provides the same functionality as ``registerForInAppForms(configuration:)`` but allows
    /// specifying a custom asset source for testing purposes.
    ///
    /// - Parameters:
    ///   - configuration: Configuration options for In-App Forms, including session timeout duration.
    ///     Defaults to a 1-hour session timeout.
    ///   - assetSource: A custom source URL for the form assets.
    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func registerForInAppForms(configuration: InAppFormsConfig = InAppFormsConfig(), assetSource: String) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.initializeIAF(
                    configuration: configuration,
                    assetSource: assetSource
                )
            }
        }
    }
}
