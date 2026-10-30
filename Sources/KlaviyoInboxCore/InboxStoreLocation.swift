//
//  InboxStoreLocation.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/29/26.
//

import Foundation

extension InboxAppGroup {
    package static let inboxDirectoryName = "KlaviyoInbox"

    /// The directory inside the App Group that holds the Inbox store and the company context file,
    /// created if it does not exist yet. Nil when the App Group identifier is missing, the container
    /// is unreachable, or the directory cannot be created.
    package func inboxDirectory() -> URL? {
        guard let identifier = identifier(), let container = containerURL(identifier) else { return nil }
        let directory = container.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return directory
    }
}
