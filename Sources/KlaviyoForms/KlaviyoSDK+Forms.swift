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

    /// Registers the app to receive and display in-app forms from Klaviyo.
    ///
    /// Call this after initializing `KlaviyoSDK`, typically at launch:
    ///
    /// ```swift
    /// import KlaviyoForms
    /// import KlaviyoSwift
    ///
    /// KlaviyoSDK()
    ///     .initialize(with: "YOUR_PUBLIC_API_KEY")
    ///     .registerForInAppForms()
    /// ```
    ///
    /// The SDK loads your forms and shows one whenever its targeting and behavior settings in your
    /// Klaviyo account are met, for example after an event you track. Registering again while
    /// already registered has no effect; to change the configuration, call
    /// ``unregisterFromInAppForms()`` first.
    ///
    /// - Note: Forms need your public API key, so call `KlaviyoSDK().initialize(with:)` first. If
    ///   the API key changes later, forms reload for the new account automatically.
    /// - Parameter configuration: Options for in-app forms. The default uses a one-hour session
    ///   timeout; see ``InAppFormsConfig``.
    /// - Returns: The SDK instance, for chaining.
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

    /// Stops displaying in-app forms and releases their resources.
    ///
    /// Any form on screen is dismissed, and the SDK tears down the web view and listeners used for
    /// forms. Call ``registerForInAppForms(configuration:)`` to show forms again.
    ///
    /// - Returns: The SDK instance, for chaining.
    @MainActor
    @discardableResult
    public func unregisterFromInAppForms() -> Self {
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
    /// Registering again replaces the previous handler.
    ///
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
    /// - Parameter handler: A closure that receives each ``FormLifecycleEvent``.
    /// - Returns: The SDK instance, for chaining.
    @MainActor
    @discardableResult
    public func registerFormLifecycleHandler(_ handler: @escaping (FormLifecycleEvent) -> Void) -> Self {
        IAFPresentationManager.shared.registerFormLifecycleHandler(handler)
        return self
    }

    /// Removes the handler registered with ``registerFormLifecycleHandler(_:)``.
    ///
    /// - Returns: The SDK instance, for chaining.
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
