//
//  KlaviyoExtension.swift
//
//
//  Created by Ajay Subramanya on 6/23/23.
//

import Foundation
import OSLog
import UserNotifications

private enum KlaviyoBadgeConfig {
    case incrementOne
    case setCount
    case setProperty
    case unknown(value: String)

    init(rawValue: String) {
        switch rawValue {
        case "increment_one": self = .incrementOne
        case "set_count": self = .setCount
        case "set_property": self = .setProperty
        default: self = .unknown(value: rawValue)
        }
    }
}

/// Entry points for your app's Notification Service Extension.
///
/// Forward both `UNNotificationServiceExtension` callbacks to `KlaviyoExtensionSDK`:
///
/// ```swift
/// import KlaviyoSwiftExtension
/// import UserNotifications
///
/// class NotificationService: UNNotificationServiceExtension {
///     var request: UNNotificationRequest!
///     var contentHandler: ((UNNotificationContent) -> Void)?
///     var bestAttemptContent: UNMutableNotificationContent?
///
///     override func didReceive(
///         _ request: UNNotificationRequest,
///         withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
///     ) {
///         self.request = request
///         self.contentHandler = contentHandler
///         bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
///
///         if let bestAttemptContent {
///             KlaviyoExtensionSDK.handleNotificationServiceDidReceivedRequest(
///                 request: request,
///                 bestAttemptContent: bestAttemptContent,
///                 contentHandler: contentHandler
///             )
///         }
///     }
///
///     override func serviceExtensionTimeWillExpire() {
///         if let contentHandler, let bestAttemptContent {
///             KlaviyoExtensionSDK.handleNotificationServiceExtensionTimeWillExpireRequest(
///                 request: request,
///                 bestAttemptContent: bestAttemptContent,
///                 contentHandler: contentHandler
///             )
///         }
///     }
/// }
/// ```
///
/// To update badge counts, the extension and your app must share an App Group, named by the
/// `klaviyo_app_group` key in both targets' `Info.plist` files.
public enum KlaviyoExtensionSDK {
    /// Prepares a Klaviyo push notification for display: updates the badge, adds action buttons and
    /// attaches rich media.
    ///
    /// Call this from `UNNotificationServiceExtension.didReceive(_:withContentHandler:)`. The SDK:
    ///
    /// - Updates the badge count if the payload asks it to, and saves the new count to the shared
    ///   App Group so `KlaviyoSDK` stays in sync. This requires the `klaviyo_app_group`
    ///   `Info.plist` key.
    /// - Adds the action buttons defined in the payload, unless the notification already has a
    ///   category.
    /// - Downloads the image or video in the payload, attaches it to the notification and calls
    ///   `contentHandler`. If there's no media, or the download fails, it calls `contentHandler`
    ///   with the content as it is.
    ///
    /// iOS limits how long the extension can run. If the download doesn't finish in time, iOS calls
    /// `serviceExtensionTimeWillExpire()`. Forward that call to
    /// ``handleNotificationServiceExtensionTimeWillExpireRequest(request:bestAttemptContent:contentHandler:)``
    /// so the notification is delivered without the media.
    ///
    /// - Parameters:
    ///   - request: The request passed to `didReceive(_:withContentHandler:)`.
    ///   - bestAttemptContent: A mutable copy of the request's content. The SDK modifies it and
    ///     passes it to `contentHandler`.
    ///   - contentHandler: The content handler passed to `didReceive(_:withContentHandler:)`. The SDK
    ///     calls it once the notification is ready.
    ///   - fallbackMediaType: The file extension to give the downloaded media when the payload
    ///     doesn't specify one in `rich-media-type`. Defaults to `"jpg"`.
    public static func handleNotificationServiceDidReceivedRequest(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        fallbackMediaType: String = "jpg"
    ) {
        // handle badge setting from the push notification payload
        handleBadge(bestAttemptContent: bestAttemptContent)
        // handle dynamic action buttons
        handleActionButtons(request: request, bestAttemptContent: bestAttemptContent)
        // handle rich media setup
        handleRichMedia(bestAttemptContent: bestAttemptContent, contentHandler: contentHandler, fallbackMediaType: fallbackMediaType)
    }

    /// reads the badge count configuration setting received in the payload and handles it accordingly and syncs to the stored count
    /// - Parameters:
    ///   - bestAttemptContent: the best attempt at mutating the APNS payload before attaching it to the push notification
    private static func handleBadge(bestAttemptContent: UNMutableNotificationContent) {
        guard let badgeConfigValue = bestAttemptContent.userInfo["badge_config"] as? String else { return }
        // retrieve the app group user defaults used to store the count
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "klaviyo_app_group") as? String,
              let userDefaults = UserDefaults(suiteName: appGroup) else { return }

        // update the badge value according to the configuration
        var newBadgeValue: Int?
        let badgeConfig = KlaviyoBadgeConfig(rawValue: badgeConfigValue)
        switch badgeConfig {
        case .incrementOne:
            let currentBadgeCount = userDefaults.integer(forKey: "badgeCount")
            newBadgeValue = currentBadgeCount + 1
        case .setCount, .setProperty:
            if let badgeValue = bestAttemptContent.userInfo["badge_value"] as? Int {
                newBadgeValue = badgeValue
            }
        case .unknown:
            return
        }

        // store the count and set that updated value to the push payload
        userDefaults.set(newBadgeValue, forKey: "badgeCount")
        bestAttemptContent.badge = newBadgeValue as? NSNumber
    }

    /// sets up the rich media (images or videos) for a rich push, parameters given by `handleNotificationServiceDidReceivedRequest(:)`
    /// - Parameters:
    ///   - bestAttemptContent: the best attempt at mutating the APNS payload before attaching it to the push notification
    ///   - contentHandler: the closure that needs to be called before the time iOS provides for us to mutate the content
    private static func handleRichMedia(
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        fallbackMediaType: String = "jpg"
    ) {
        // 1a. get the rich media url from the push notification payload
        guard let mediaURLString = bestAttemptContent.userInfo["rich-media"] as? String else {
            contentHandler(bestAttemptContent)
            return
        }

        // 1b.falling back to .png in case the media type isn't sent from the server.
        let mediaTypeString = bestAttemptContent.userInfo["rich-media-type"] as? String ?? fallbackMediaType

        // 2. once we have the url lets download the media from the server
        downloadMedia(for: mediaURLString) { localFileURL in
            guard let localFileURL = localFileURL else {
                contentHandler(bestAttemptContent)
                return
            }

            let localFilePathWithTypeString = "\(localFileURL.path).\(mediaTypeString)"

            // 3. once we have the local file URL we will create an attachment
            createAttachment(
                localFileURL: localFileURL,
                localFilePathWithTypeString: localFilePathWithTypeString
            ) { attachment in
                guard let attachment = attachment else {
                    contentHandler(bestAttemptContent)
                    return
                }

                // 4. assign the create attachement to the best attempt content attachment and call the content handler so that the notification with the
                //    media can be delivered to the user.
                bestAttemptContent.attachments = [attachment]
                contentHandler(bestAttemptContent)
            }
        }
    }

    /// Delivers a Klaviyo push notification before the extension's time runs out.
    ///
    /// Call this from `UNNotificationServiceExtension.serviceExtensionTimeWillExpire()`. The SDK adds
    /// the payload's action buttons, then calls `contentHandler` with `bestAttemptContent`, without
    /// any media that hasn't finished downloading.
    ///
    /// - Parameters:
    ///   - request: The request passed to `didReceive(_:withContentHandler:)`.
    ///   - bestAttemptContent: The mutable content you passed to
    ///     `handleNotificationServiceDidReceivedRequest(request:bestAttemptContent:contentHandler:)`.
    ///   - contentHandler: The content handler passed to `didReceive(_:withContentHandler:)`.
    public static func handleNotificationServiceExtensionTimeWillExpireRequest(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // Still try to register action buttons before timeout
        handleActionButtons(request: request, bestAttemptContent: bestAttemptContent)
        contentHandler(bestAttemptContent)
    }

    /// downloads the media from the provided URL and writes to disk and provides a URL to the data on disk
    /// - Parameters:
    ///   - urlString: the URL from where the media needs to be downloaded
    ///   - completion: closure that would be called when the media has finished downloading and the URL to the data on disk is available.
    ///                 note that in the case of failure the closure will still be called but with `nil`.
    private static func downloadMedia(
        for urlString: String,
        completion: @escaping (URL?) -> Void
    ) {
        guard let mediaURL = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.downloadTask(with: mediaURL) { file, _, error in
            if let error = error {
                if #available(iOS 14.0, *) {
                    Logger.richMedia.error("Error when downloading push media: \(error.localizedDescription)")
                }
                completion(nil)
                return
            }

            guard let file = file else {
                completion(nil)
                return
            }

            completion(file)
        }.resume()
    }

    /// creates an attachment that can be attached to the push notification
    /// - Parameters:
    ///   - localFileURL: the location of the downloaded file from the download task
    ///   - localFilePathWithTypeString: the location that we want to move the file to with the file extension received from the server
    ///   - completion: closure that will be called once the file has been moved and an attachment has been created.
    ///                 Note that in the case of failure during file transfer or creating an attachment this closure will be called with `nil` indicating a failure.
    private static func createAttachment(
        localFileURL: URL,
        localFilePathWithTypeString: String,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let localFileURLWithType: URL
        if #available(iOS 16.0, *) {
            localFileURLWithType = URL(filePath: localFilePathWithTypeString)
        } else {
            localFileURLWithType = URL(fileURLWithPath: localFilePathWithTypeString)
        }

        do {
            try FileManager.default.moveItem(at: localFileURL, to: localFileURLWithType)
        } catch {
            completion(nil)
            return
        }

        guard let attachment = try? UNNotificationAttachment(
            identifier: "",
            url: localFileURLWithType,
            options: nil
        )
        else {
            completion(nil)
            return
        }

        completion(attachment)
    }

    /// Handles dynamic action button registration from push notification payload
    /// - Parameters:
    ///   - request: the notification request
    ///   - bestAttemptContent: the best attempt at mutating the APNS payload before attaching it to the push notification
    private static func handleActionButtons(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent
    ) {
        // Respect developer-set categories for non-Klaviyo notifications
        // Only process and set up action buttons for Klaviyo notifications
        let existingCategory = request.content.categoryIdentifier
        guard bestAttemptContent.isKlaviyoNotification && existingCategory.isEmpty else {
            return
        }

        // Parse action buttons from payload
        guard let buttonDefs = KlaviyoActionButtonParser.parseActionButtons(from: bestAttemptContent.userInfo) else {
            return
        }

        // Create actions
        let actions = KlaviyoActionButtonParser.createActions(from: buttonDefs)

        // Generate unique category identifier for this notification
        let uniqueSuffix = request.identifier.isEmpty ? UUID().uuidString : request.identifier
        let categoryIdentifier = "\(KlaviyoCategoryManager.categoryIdentifierPrefix)\(uniqueSuffix)"

        // Register category dynamically with unique identifier
        KlaviyoCategoryManager.shared.registerCategory(categoryIdentifier: categoryIdentifier, actions: actions)

        // Set category on notification content
        bestAttemptContent.categoryIdentifier = categoryIdentifier
    }
}
