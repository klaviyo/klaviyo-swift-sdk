//
//  UNNotificationResponse+Klaviyo.swift
//
//  Klaviyo Swift SDK
//
//  Created for Klaviyo
//
//  Copyright (c) 2025 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation
import UserNotifications

extension UNNotificationResponse {
    /// Determines if a notification originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    public var isKlaviyoNotification: Bool {
        guard let properties = notification.request.content.userInfo as? [String: Any],
              let body = properties["body"] as? [String: Any] else {
            return false
        }

        return body["_k"] != nil
    }

    /// Returns the custom Klaviyo properties from a Klaviyo notification payload, if present.
    public var klaviyoProperties: [String: Any]? {
        guard isKlaviyoNotification else {
            return nil
        }

        guard let properties = notification.request.content.userInfo as? [String: Any] else {
            return nil
        }

        return properties
    }

    /// Returns the deep link URL from a Klaviyo notification payload, if present.
    public var klaviyoDeepLinkURL: URL? {
        guard isKlaviyoNotification else {
            return nil
        }

        guard let properties = klaviyoProperties else {
            return nil
        }

        guard let urlString = properties["url"] as? String else {
            return nil
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        return url
    }
}
