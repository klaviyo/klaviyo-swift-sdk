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
    /// This method sets up the necessary lifecycle event handlers and constructs the web view
    /// that will be used to display In-App Forms. The forms will be displayed based on your
    /// Klaviyo form display settings.
    ///
    /// - Parameter configuration: Configuration options for In-App Forms, including session timeout duration.
    ///   Defaults to a 1-hour session timeout.
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
