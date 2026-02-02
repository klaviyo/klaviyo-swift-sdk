//
//  KlaviyoExtension.swift
//
//
//  Created by Ajay Subramanya on 6/23/23.
//
import Foundation
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

public enum KlaviyoExtensionSDK {
    /// Call this method when you receive a rich push notification in the notification service extension.
    /// This method should be called from within `didReceive(_:withContentHandler:)` method of `UNNotificationServiceExtension`.
    /// This method mainly does two things - downloads the media (images or videos) attached in the payload and then attaches it to the push notification.
    ///
    /// NOTE that there is no guarantee that the content handler will be called with in the time stipulated by iOS to download the rich media successfully.
    /// In the case where the download does not complete, iOS will automatically present the notification as received from APNS without the attached media
    ///
    /// - Parameters:
    ///   - request: the request received in the delegate `didReceive(_:withContentHandler:)`
    ///   - bestAttemptContent: this is also received in `didReceive(_:withContentHandler:)` and is the best attempt at mutating the APNS payload before attaching it to the push notification
    ///   - contentHandler: this is also received in `didReceive(_:withContentHandler:)` and is the closure that needs to be called before the time iOS provides for us to mutate the content. This closure will be called with the `bestAttemptContent` once the media is downloaded and attached.
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
                print("error when downloading push media = \(error.localizedDescription)")
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
        guard bestAttemptContent.userInfo.isKlaviyoNotification() && existingCategory.isEmpty else {
            return
        }

        // Parse action buttons from payload
        guard let buttonDefs = KlaviyoActionButtonParser.parseActionButtons(
            from: bestAttemptContent.userInfo
        ) else {
            return
        }

        // Get notification ID for unique category
        guard let body = bestAttemptContent.userInfo["body"] as? [String: Any],
              let notificationId = body["_k"] as? String else {
            return
        }

        // Create actions
        let actions = KlaviyoActionButtonParser.createActions(from: buttonDefs)

        // Register category dynamically
        let categoryId = KlaviyoCategoryController.shared.registerCategory(
            notificationId: notificationId,
            actions: actions
        )

        // Set category on notification content
        bestAttemptContent.categoryIdentifier = categoryId
    }
}
