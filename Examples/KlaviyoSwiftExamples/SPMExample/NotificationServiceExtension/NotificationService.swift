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

        if let bestAttemptContent = bestAttemptContent {
            /// Check if you have a value of rich-media. If not, call the content handler to deliver the push and return
            guard let imageURLString =
                bestAttemptContent.userInfo["rich-media"] as? String else {
                contentHandler(bestAttemptContent)
                return
            }

            /// Call the convenience method to retrieve the image with the URL received from the push payload.
            getMedia(for: imageURLString) { [weak self] image in
                /// When the completion block fires and the image was downloaded successfully save it to disk
                /// and get the file URL else call the completion handler and return
                guard
                    let self = self,
                    let image = image,
                    let fileURL = self.saveImageAttachment(
                        image: image,
                        forIdentifier: "attachment.png")
                else {
                    contentHandler(bestAttemptContent)
                    return
                }

                /// Create a UNNotificationAttachment with the file URL. Name the identifier image to set it as the image on the final notification.
                let imageAttachment = try? UNNotificationAttachment(
                    identifier: "image",
                    url: fileURL,
                    options: nil)

                /// If creating the attachment succeeds, add it to the attachments property on bestAttemptContent.
                if let imageAttachment = imageAttachment {
                    bestAttemptContent.attachments = [imageAttachment]
                }

                /// Call the content handler to deliver the push notification.
                /// NOTE: if this doesn't happen before the stipulated time then the completion handler is called with
                /// the bestAttemptContent from the `serviceExtensionTimeWillExpire` function
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
    private func getMedia(
        for urlString: String,
        completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        downloadImage(forURL: url) { result in
            switch result {
            case let .success(image):
                completion(image)
            case let .failure(error):
                print("received error [\(error.localizedDescription)]")
                completion(nil)
            }
        }
    }

    private func saveImageAttachment(
        image: UIImage,
        forIdentifier identifier: String) -> URL? {
        /// Obtain a reference to the temp file directory.
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

        /// Using the temp file directory, create a directory URL using a unique string.
        let directoryPath = tempDirectory.appendingPathComponent(
            ProcessInfo.processInfo.globallyUniqueString,
            isDirectory: true)

        do {
            /// The FileManager is responsible for creating the actual file to store the data.
            /// Call `createDirectory(at:winthIntermediateDirectories:attributes:)` to create an empty directory
            try FileManager.default.createDirectory(
                at: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil)

            /// Create a file URL based on the image identifier.
            let fileURL = directoryPath.appendingPathComponent(identifier)

            /// Create a Data object from the image.
            guard let imageData = image.pngData() else {
                return nil
            }

            /// Attempt to write the file to disk.
            try imageData.write(to: fileURL)

            return fileURL
        } catch {
            return nil
        }
    }

    private func downloadImage(
        forURL url: URL,
        completion: @escaping (Result<UIImage, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(DownloadError.emptyData))
                return
            }

            guard let image = UIImage(data: data) else {
                completion(.failure(DownloadError.invalidImage))
                return
            }

            completion(.success(image))
        }
        task.resume()
    }

    enum DownloadError: Error {
        case emptyData
        case invalidImage
    }
}
