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
    @discardableResult
    public func registerForInAppForms(configuration: InAppFormsConfig = InAppFormsConfig()) -> KlaviyoSDK {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.initializeIAF(configuration: configuration)
            }
        }
        return self
    }

    /// Unregisters app from receiving In-App Forms and cleans up resources associated with In-App Forms (e.g. web view resources, subscriptions, state)
    @MainActor
    @discardableResult
    public func unregisterFromInAppForms() -> KlaviyoSDK {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.destroyWebviewAndListeners()
            }
        }

        return self
    }

    /// Registers a handler to be called when form lifecycle events occur.
    ///
    /// The handler will be invoked when:
    /// - A form is shown (``FormLifecycleEvent/formShown``)
    /// - A form is dismissed (``FormLifecycleEvent/formDismissed``)
    /// - A user taps a CTA in a form (``FormLifecycleEvent/formCTAClicked``)
    ///
    /// The handler is called on the main thread.
    ///
    /// Example usage:
    /// ```swift
    /// KlaviyoSDK().registerFormLifecycleHandler { event in
    ///     switch event {
    ///     case .formShown:
    ///         Analytics.track("Form Shown")
    ///     case .formDismissed:
    ///         Analytics.track("Form Dismissed")
    ///     case .formCTAClicked:
    ///         Analytics.track("Form CTA Clicked")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter handler: A closure receiving the lifecycle event.
    /// - Returns: A KlaviyoSDK instance for chaining.
    @MainActor
    @discardableResult
    public func registerFormLifecycleHandler(_ handler: @escaping (FormLifecycleEvent) -> Void) -> KlaviyoSDK {
        IAFPresentationManager.shared.registerFormLifecycleHandler(handler)
        return self
    }

    /// Unregisters any form lifecycle handler that was previously registered.
    ///
    /// - Returns: A KlaviyoSDK instance for chaining.
    @MainActor
    @discardableResult
    public func unregisterFormLifecycleHandler() -> KlaviyoSDK {
        IAFPresentationManager.shared.unregisterFormLifecycleHandler()
        return self
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
