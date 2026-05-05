//
//  UNNotificationContent+Klaviyo.swift
//

import Foundation
import UserNotifications

extension Dictionary where Key == AnyHashable {
    /// Determines if a notification payload originated from Klaviyo.
    ///
    /// A notification is considered a Klaviyo notification if it contains
    /// a "body" dictionary with a "_k" key in its userInfo.
    func isKlaviyoNotification() -> Bool {
        guard let properties = self as? [String: Any],
              let body = properties["body"] as? [String: Any],
              body["_k"] != nil else {
            return false
        }
        return true
    }
}

extension UNNotificationContent {
    /// Determines if this notification content originated from Klaviyo.
    var isKlaviyoNotification: Bool {
        userInfo.isKlaviyoNotification()
    }
}
