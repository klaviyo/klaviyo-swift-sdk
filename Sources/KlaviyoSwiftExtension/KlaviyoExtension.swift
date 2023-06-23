//
//  File.swift
//  
//
//  Created by Ajay Subramanya on 6/23/23.
//

import Foundation
import UIKit

public struct KlaviyoExtensionSDK {
    /// Default initializer for the Klaviyo SDK.
    public init() {}
    
    /// Call this method when you receive a rich push notification in the notification service extension.
    /// This method should be called from within `didReceive(_:withContentHandler:)` method of `UNNotificationServiceExtension`.
    /// This method mainly does two things - downloads the media attached in the payload and then attaches it to the push notification.
    ///
    /// NOTE that there is no guarantees that the content handler will be called within the iOS stipulated time in the case where the download of the rich media takes long. iOS will automatically
    /// present the notification as received from APNS when this happens and the image will not be attached to the notification.
    ///
    /// - Parameters:
    ///   - request: the request received in the delegate `didReceive(_:withContentHandler:)`
    ///   - bestAttemptContent: this is also received in `didReceive(_:withContentHandler:)` and is the best attempt at mutating the APNS payload before attaching it to the push notification
    ///   - contentHandler: this is also received in `didReceive(_:withContentHandler:)` and is the closure that needs to be called before the time iOS provides for us to mutate the content. This closure will be called with the `bestAttemptContent` once the image is downloaded and attached.
    public func handleNotificationServiceDidReceivedRequest(
         request: UNNotificationRequest,
         bestAttemptContent: UNMutableNotificationContent,
         contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // 1a. get the rich media url from the push notification payload
        guard let imageURLString = bestAttemptContent.userInfo["rich-media"] as? String else {
            contentHandler(bestAttemptContent)
            return
        }

        // 1b.falling back to .png in case the media type isn't sent from the server.
        let imageTypeString = bestAttemptContent.userInfo["rich-media-type"] as? String ?? "png"

        // 2. once we have the url lets download the media from the server
        downloadMedia(for: imageURLString) { localFileURL in
            guard let localFileURL = localFileURL else {
                contentHandler(bestAttemptContent)
                return
            }

            let localFilePathWithTypeString = "\(localFileURL.path).\(imageTypeString)"

            // 3. once we have the local file URL we will create an attachment
            createAttachment(
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
    
    public func handleNotificationServiceExtensionTimeWillExpireRequest(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        contentHandler(bestAttemptContent)
    }
    
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
                print("error when downloading push media = \(error.localizedDescription)")
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
