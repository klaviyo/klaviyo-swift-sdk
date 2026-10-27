//
//  KlaviyoSDK+Forms.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 2/20/25.
//

import Foundation
import KlaviyoCore

/// Controls whether in-app form WebView console messages are relayed to the native logger.
///
/// This is disabled by default. Hosts can enable it for diagnostic builds without relying on
/// process environment variables, which are unavailable to TestFlight users.
final class WebConsoleLoggingConfig: @unchecked Sendable {
    static let shared = WebConsoleLoggingConfig()

    private let lock = NSLock()
    private var _isEnabled = false

    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isEnabled = newValue
        }
    }
}

extension KlaviyoSDKModule {
    /// Enables or disables relaying JavaScript console output from in-app forms to the native logger.
    ///
    /// Disabled by default. This setting applies when the next in-app form WebView is created.
    /// - Parameter enabled: Whether to relay WebView console output.
    /// - Returns: The current SDK instance, for chaining.
    @_spi(KlaviyoPrivate)
    @discardableResult
    public func setWebConsoleLoggingEnabled(_ enabled: Bool) -> Self {
        WebConsoleLoggingConfig.shared.isEnabled = enabled
        return self
    }

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
    public func registerForInAppForms(configuration: InAppFormsConfig = InAppFormsConfig()) -> Self {
        Task {
            await MainActor.run {
                IAFPresentationManager.shared.initializeIAF(configuration: configuration)
            }
        }
        return self
    }

    /// Starts a draft in-app forms preview session with a preview token from the Klaviyo form
    /// editor.
    ///
    /// Starting a preview is like unregistering and registering again: if forms are registered,
    /// the current session is torn down, dismissing any form on screen, and a new session starts
    /// that loads draft forms for `token`. If ``registerForInAppForms(configuration:)`` hasn't
    /// been called yet, the token is held and the preview starts when forms register; no forms are
    /// shown before then.
    ///
    /// A preview token is a short-lived credential for on-device testing of draft forms. It is not
    /// for production use: never ship a preview token in a release build. The token is held in
    /// memory only and is never persisted or logged. A malformed token is ignored with a warning
    /// and changes nothing. When the preview expires, the token is cleared and published forms
    /// return in the next session, such as after the next app launch.
    /// ``unregisterFromInAppForms()`` also clears it.
    ///
    /// - Parameter token: The preview token.
    /// - Returns: The current SDK instance, for chaining.
    @MainActor
    @discardableResult
    public func startFormsPreview(_ token: String) -> Self {
        FormsPreviewTokenStore.shared.startPreview(token)
        return self
    }

    /// Ends the draft in-app forms preview session started by ``startFormsPreview(_:)``. If forms
    /// are registered, the current session is torn down, dismissing any form on screen, and a new
    /// session starts that loads published forms.
    ///
    /// - Returns: The current SDK instance, for chaining.
    @MainActor
    @discardableResult
    public func endFormsPreview() -> Self {
        FormsPreviewTokenStore.shared.endPreview()
        return self
    }

    /// Unregisters app from receiving In-App Forms and cleans up resources associated with In-App Forms (e.g. web view resources, subscriptions, state)
    @MainActor
    @discardableResult
    public func unregisterFromInAppForms() -> Self {
        // Registering again loads published forms
        FormsPreviewTokenStore.shared.clear()
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
    /// - A form is shown (``FormLifecycleEvent/formShown(formId:formName:)``)
    /// - A form is dismissed (``FormLifecycleEvent/formDismissed(formId:formName:)``)
    /// - A user taps a CTA in a form, whether it opens an in-app deep link or an external/system
    ///   URL (``FormLifecycleEvent/formCtaClicked(formId:formName:buttonLabel:deepLinkUrl:)``)
    ///
    /// Each event case carries contextual data including `formId`, `formName`, and
    /// CTA-specific fields (`buttonLabel`, `deepLinkUrl`) where applicable.
    ///
    /// The handler is called on the main thread.
    ///
    /// Example usage:
    /// ```swift
    /// KlaviyoSDK().registerFormLifecycleHandler { event in
    ///     switch event {
    ///     case .formShown(let formId, let formName):
    ///         Analytics.track("Form Shown", properties: ["formId": formId])
    ///     case .formDismissed(let formId, let formName):
    ///         Analytics.track("Form Dismissed", properties: ["formId": formId])
    ///     case .formCtaClicked(let formId, let formName, let buttonLabel, let deepLinkUrl):
    ///         Analytics.track("Form CTA Clicked", properties: [
    ///             "formId": formId,
    ///             "buttonLabel": buttonLabel,
    ///             "url": deepLinkUrl.absoluteString
    ///         ])
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter handler: A closure receiving the ``FormLifecycleEvent`` with all contextual data.
    /// - Returns: A KlaviyoSDK instance for chaining.
    @MainActor
    @discardableResult
    public func registerFormLifecycleHandler(_ handler: @escaping (FormLifecycleEvent) -> Void) -> Self {
        IAFPresentationManager.shared.registerFormLifecycleHandler(handler)
        return self
    }

    /// Unregisters any form lifecycle handler that was previously registered.
    ///
    /// - Returns: A KlaviyoSDK instance for chaining.
    @MainActor
    @discardableResult
    public func unregisterFormLifecycleHandler() -> Self {
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
