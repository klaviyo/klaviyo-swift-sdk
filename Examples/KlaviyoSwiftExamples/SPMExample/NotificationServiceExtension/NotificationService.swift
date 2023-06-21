//
//  NotificationService.swift
//  NotificationServiceExtension
//
//  Created by Ajay Subramanya on 6/14/23.
//

import UIKit
import UserNotifications

// MARK: notification service extension implementation.

/// When push payload is marked as there being mutable-content this service
/// (more specifically the `didReceiveNotificationRequest` ) is called to perform
/// tasks such as downloading images and attaching it to the notification before it's displayed to the user.
///
/// There is a limited time before which `didReceiveNotificationRequest`  needs to wrap up it's operations
/// else the notification is displayed as received.
///
/// Any property from `UNMutableNotificationContent` can be mutated here before presenting the notification.
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            return
        }

        // 1a. get the rich media url from the push notification payload
        guard let imageURLString = bestAttemptContent.userInfo["rich-media"] as? String else {
            contentHandler(bestAttemptContent)
            return
        }

        // 1b.falling back to .png in case the media type isn't sent from the server.
        let imageTypeString = bestAttemptContent.userInfo["rich-media-type"] as? String ?? "png"

        // 2. once we have the url lets download the media from the server
        downloadMedia(for: imageURLString) { [weak self] localFileURL in
            guard let localFileURL = localFileURL else {
                contentHandler(bestAttemptContent)
                return
            }

            let localFilePathWithTypeString = "\(localFileURL.path).\(imageTypeString)"

            // 3. once we have the local file URL we will create an attachment
            self?.createAttachment(
                localFileURL: localFileURL,
                localFilePathWithTypeString: localFilePathWithTypeString) { attachment in
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

    override func serviceExtensionTimeWillExpire() {
        /// Called just before the extension will be terminated by the system.
        /// Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}

// MARK: supporting methods to notification service

extension NotificationService {
    /// downloads the media from the provided URL and writes to disk and provides a URL to the data on disk
    /// - Parameters:
    ///   - urlString: the URL from where the media needs to be downloaded
    ///   - completion: closure that would be called when the image has finished downloading and the URL to the data on disk is available.
    ///                 note that in the case of failure the closure will still be called but with `nil`.
    private func downloadMedia(
        for urlString: String,
        completion: @escaping (URL?) -> Void) {
        guard let imageURL = URL(string: urlString) else {
            completion(nil)
            return
        }

        let task = URLSession.shared.downloadTask(with: imageURL) { file, _, error in
            if let error = error {
                print("error when downloading image = \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let file = file else {
                completion(nil)
                return
            }

            completion(file)
        }
        task.resume()
    }

    /// creates an attachment that can be attached to the push notification
    /// - Parameters:
    ///   - localFileURL: the location of the downloaded file from the download task
    ///   - localFilePathWithTypeString: the location that we want to move the file to with the file extension received from the server
    ///   - completion: closure that will be called once the file has been moved and an attachment has been created.
    ///                 Note that in the case of failure during file transfer or creating an attachment this closure will be called with `nil` indicating a failure.
    private func createAttachment(
        localFileURL: URL,
        localFilePathWithTypeString: String,
        completion: @escaping (UNNotificationAttachment?) -> Void) {
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
            options: nil) else {
            completion(nil)
            return
        }

        completion(attachment)
    }
}
