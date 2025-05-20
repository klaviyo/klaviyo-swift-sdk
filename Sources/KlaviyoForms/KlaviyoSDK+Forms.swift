//
//  KlaviyoSDK+Forms.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/20/25.
//

import Foundation
import KlaviyoSwift

extension KlaviyoSDK {
    /// Registers app to receive and display in-app forms from Klaviyo.
    ///
    /// This method sets up the necessary lifecycle event handlers and constructs the web view
    /// that will be used to display in-app forms. The forms will be displayed based on your
    /// Klaviyo form display settings.
    ///
    /// - Parameter configuration: Configuration options for in-app forms, including session timeout duration.
    ///   Defaults to a 1-hour session timeout.
    @MainActor
    public func registerForInAppForms(configuration: IAFConfiguration = IAFConfiguration()) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.setupLifecycleEvents(configuration: configuration)
                IAFPresentationManager.shared.constructWebview()
            }
        }
    }

    /// Unregisters app from receiving in-app forms and cleans up resources associated with in-app forms (e.g. web view resources, subscriptions, state)
    @MainActor
    public func unregisterFromInAppForms() {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.destroyWebviewAndListeners()
            }
        }
    }

    /// Registers app to receive and display in-app forms from Klaviyo with a custom asset source.
    ///
    /// This method is for internal use only and should not be used in production applications.
    /// It provides the same functionality as ``registerForInAppForms(configuration:)`` but allows
    /// specifying a custom asset source for testing purposes.
    ///
    /// - Parameters:
    ///   - configuration: Configuration options for in-app forms, including session timeout duration.
    ///     Defaults to a 1-hour session timeout.
    ///   - assetSource: A custom source URL for the form assets.
    @MainActor
    @_spi(KlaviyoPrivate)
    @available(*, deprecated, message: "This function is for internal use only, and should not be used in production applications")
    public func registerForInAppForms(configuration: IAFConfiguration = IAFConfiguration(), assetSource: String) {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.setupLifecycleEvents(configuration: configuration)
                IAFPresentationManager.shared.constructWebview(assetSource: assetSource)
            }
        }
    }
}
