//
//  DeepLinkHandler.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/15/25.
//

import OSLog
import UIKit

public class DeepLinkHandler {
    // MARK: - Custom Deep Link Handler

    private var customDeepLinkHandler: (@MainActor (URL) -> Void)?

    package func registerCustomHandler(_ handler: @escaping (URL) -> Void) {
        if #available(iOS 14.0, *) {
            Logger.navigation.log("Registering a custom deep link handler")
        }
        customDeepLinkHandler = handler
    }

    package func unregisterCustomHandler() {
        if #available(iOS 14.0, *) {
            if customDeepLinkHandler != nil {
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
        customDeepLinkHandler = nil
    }

    package var hasCustomHandler: Bool {
        customDeepLinkHandler != nil
    }

    // MARK: - Handle Link

    /// Attempts to route a Universal Link using the host application's Scene Delegate or App Delegate link handlers
    package func openURL(_ url: URL) async {
        if let customDeepLinkHandler {
            if #available(iOS 14.0, *) {
                Logger.navigation.info("Handling URL: '\(url.absoluteString, privacy: .public)' using registered deep link handler")
            }
            await MainActor.run {
                customDeepLinkHandler(url)
            }
        } else {
            if #available(iOS 14.0, *) {
                Logger.navigation.info("A deep link handler has not been registered.\nHandling URL: '\(url.absoluteString, privacy: .public)' using fallback deep link handler")
            }

            if ["http", "https"].contains(url.scheme?.lowercased()) {
                await Self.openWithFallbackHandler(url: url)
            } else {
                await Self.openWithUIApplicationAPI(url)
            }
        }
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

        // First try to route with the App Delegate
        if await routeWithAppDelegate(url: url) { return }

        // If that fails, try to route with the Scene Delegate
        if await routeWithSceneSessionActivation(url: url) { return }

        // If that fails, fall back to opening with `UIApplication.shared.open(_:)`
        await openWithUIApplicationAPI(url)
    }

    // MARK: - Private Routing Helpers

    /// Attempts to trigger the host app's own universal link handling logic via the Scene Delegate.
    ///
    /// - Parameter url: The universal link URL to be handled.
    /// - Returns: `true` if the link was successfully submitted or handled, and `false` otherwise.
    @MainActor
    private static func routeWithSceneSessionActivation(url: URL) async -> Bool {
        if #available(iOS 14.0, *) {
            Logger.navigation.info("Attempting to handle link via the host application's SceneDelegate.")
        }

        let activity = createUserActivity(for: url)

        if UIApplication.shared.supportsMultipleScenes {
            // Find the active scene to reuse its window.
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
                if #available(iOS 14.0, *) {
                    Logger.navigation.warning("No foreground active scene found to handle the link.")
                }
                return false
            }

            return await performSceneActivation(for: windowScene, with: activity)

        } else {
            // Fallback for single-scene devices like iPhone.
            guard let scene = UIApplication.shared.connectedScenes.first,
                  let delegate = scene.delegate else {
                if #available(iOS 14.0, *) {
                    Logger.navigation.warning("Could not find scene or delegate in single-scene path.")
                }
                return false
            }

            if delegate.responds(to: #selector(UISceneDelegate.scene(_:continue:))) {
                if delegate.scene?(scene, continue: activity) != nil {
                    return true
                } else {
                    return false
                }
            } else {
                if #available(iOS 14.0, *) {
                    Logger.navigation.warning("Delegate does not respond to scene(_:continue:). Cannot handle link.")
                }
                return false
            }
        }
    }

    /// Helper that wraps the async logic for scene activation and handles API availability.
    @MainActor
    private static func performSceneActivation(for scene: UIWindowScene, with activity: NSUserActivity) async -> Bool {
        await withCheckedContinuation { continuation in
            let errorHandler = { (error: Error) in
                if #available(iOS 14.0, *) {
                    Logger.navigation.warning("Scene activation request failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: false)
            }

            // Use the modern API on iOS 17+ and fall back to the older one.
            if #available(iOS 17.0, *) {
                let request = UISceneSessionActivationRequest(session: scene.session, userActivity: activity)
                UIApplication.shared.activateSceneSession(for: request, errorHandler: errorHandler)
            } else {
                UIApplication.shared.requestSceneSessionActivation(
                    scene.session, userActivity: activity, options: nil, errorHandler: errorHandler
                )
            }

            continuation.resume(returning: true)
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
        userActivity.userInfo = ["source": "KlaviyoSwiftSDK"]
        return userActivity
    }
}
