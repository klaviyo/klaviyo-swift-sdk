//
//  UniversalLinkHandler.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/15/25.
//

import OSLog
import UIKit

public class UniversalLinkHandler {
    private var isProcessing = false

    // MARK: - Custom Deep Link Handler

    private var deepLinkHandler: (@MainActor (URL) -> Void)?

    package func registerCustomHandler(_ handler: @escaping (URL) -> Void) {
        if #available(iOS 14.0, *) {
            Logger.navigation.log("Registering a custom deep link handler")
        }
        deepLinkHandler = handler
    }

    package func unregisterCustomHandler() {
        if #available(iOS 14.0, *) {
            if deepLinkHandler != nil {
                Logger.navigation.log("""
                Unregistering the custom deep link handler;
                SDK will revert to using fallback mechanism for handling deep links.
                """)
            } else {
                Logger.navigation.info("""
                Called `unregisterDeepLinkHandler()`, though no custom handler was registered.
                No action will be taken.
                """)
            }
            Logger.navigation.warning("""
            For improved stability and future-proofing, please provide your own
            deep link handler logic by calling `KlaviyoSDK().registerDeepLinkHandler(_:)`
            on application launch.
            """)
        }
        deepLinkHandler = nil
    }

    // MARK: - Handle Link

    /// Attempts to route a Universal Link using the host application's Scene Delegate or App Delegate link handlers
//    @MainActor
    package func open(_ url: URL) async {
        guard !isProcessing else {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("Already processing a link; skipping.")
            }
            return
        }

        isProcessing = true

        if let deepLinkHandler {
            if #available(iOS 14.0, *) {
                Logger.navigation.info("Handling URL: '\(url.absoluteString, privacy: .public)' using registered deep link handler")
            }
            await MainActor.run {
                deepLinkHandler(url)
            }
        } else {
            if #available(iOS 14.0, *) {
                Logger.navigation.info("A deep link handler has not been registered.\nHandling URL: '\(url.absoluteString, privacy: .public)' using fallback deep link handler")
            }

            if ["http", "https"].contains(url.scheme?.lowercased()) {
                //
                await Self.openWithFallbackHandler(url: url)
            } else {
                await Self.openWithUIApplicationAPI(url)
            }
        }

        isProcessing = false
    }

    @MainActor
    private static func openWithFallbackHandler(url: URL) async {
        if #available(iOS 14.0, *) {
            Logger.navigation.warning("""
            Attempting to handle universal link via a fallback mechanism.
            For improved stability and future-proofing, please provide your own
            deep link handler logic by calling `KlaviyoSDK().registerDeepLinkHandler(_:)`
            on application launch. Refer to the Klaviyo Swift SDK's README for more details.
            """)
        }

        // First try to route with the Scene Delegate
        if await routeWithSceneSessionActivation(url: url) { return }

        // If that fails, try to route with the App Delegate
        if await routeWithAppDelegate(url: url) { return }

        // If that fails, fall back to opening with `UIApplication.shared.open(_:)`
        await openWithUIApplicationAPI(url)
    }

    // MARK: - Private Routing Helpers

    /// Routes the URL using the modern SceneDelegate API.
    @MainActor
    private static func routeWithSceneSessionActivation(url: URL) async -> Bool {
        if #available(iOS 14.0, *) {
            Logger.navigation.info("Attempting to handle link via the host application's SceneDelegate.")
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("No active scene found for SceneDelegate routing.")
            }
            return false
        }

        let activity = Self.createUserActivity(for: url)

        if #available(iOS 17.0, *) {
            // Pass a closure containing the iOS 17+ API call.
            return await Self.performSceneSessionActivation { errorHandler in
                let request = UISceneSessionActivationRequest(session: windowScene.session, userActivity: activity)
                UIApplication.shared.activateSceneSession(for: request, errorHandler: errorHandler)
            }
        } else {
            // Pass a closure containing the pre-iOS 17 API call.
            return await Self.performSceneSessionActivation { errorHandler in
                UIApplication.shared.requestSceneSessionActivation(
                    windowScene.session, userActivity: activity, options: nil, errorHandler: errorHandler
                )
            }
        }
    }

    /// A private helper that wraps the shared `withCheckedContinuation` logic for the scene activation requests.
    @MainActor
    @discardableResult
    private static func performSceneSessionActivation(
        _ activationCall: @escaping (_ errorHandler: @escaping (Error) -> Void) -> Void
    ) async -> Bool {
        var continuation: CheckedContinuation<Bool, Never>?
        return await withCheckedContinuation {
            continuation = $0

            let errorHandler = { (error: Error) in
                if #available(iOS 14.0, *) {
                    Logger.navigation.log("Scene activation failed with error: \(error.localizedDescription)")
                }
                continuation?.resume(returning: false)
                continuation = nil
            }

            // Execute the specific API call passed in from the caller.
            activationCall(errorHandler)

            // The success case for the scene activation requests (both `activateSceneSession` and
            // `requestSceneSessionActivation`) is when the error handler is *not* called.
            // There's no explicit success callback. To prevent the continuation from
            // waiting forever, we optimistically resume with `true` after a very short delay.
            // This gives the system a moment to call the error handler if it's going to.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                continuation?.resume(returning: true)
                continuation = nil
            }
        }
    }

    /// Routes the URL using the AppDelegate API.
    @MainActor
    @discardableResult
    private static func routeWithAppDelegate(url: URL) async -> Bool {
        if #available(iOS 14.0, *) {
            Logger.navigation.info("Attempting to handle link via the host application's AppDelegate.")
        }
        let activity = Self.createUserActivity(for: url)

        if let delegate = UIApplication.shared.delegate,
           delegate.application?(
               UIApplication.shared, continue: activity, restorationHandler: { _ in }
           ) == true {
            return true
        } else {
            return false
        }
    }

    /// Fallback that attempts to open the URL using ``UIApplication.shared.open(_:)``.
    @MainActor
    @discardableResult
    private static func openWithUIApplicationAPI(_ url: URL) async -> Bool {
        if #available(iOS 14.0, *) {
            Logger.navigation.info("Attempting to handle link via UIApplication API.")
        }

        if await UIApplication.shared.open(url) {
            if #available(iOS 14.0, *) {
                Logger.navigation.info("Successfully opened link via UIApplication API.")
            }
            return true
        } else {
            if #available(iOS 14.0, *) {
                Logger.navigation.log("System could not open link via the UIApplication API.")
            }
            return false
        }
    }

    // MARK: - Private Factory Helpers

    /// Creates a NSUserActivity to pass into the App Delegate or Scene Delegate.
    private static func createUserActivity(for url: URL) -> NSUserActivity {
        let userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        userActivity.webpageURL = url
        userActivity.userInfo = ["source": "UniversalLinkOpener"]
        return userActivity
    }
}
