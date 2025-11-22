//
//  PushActionCategories.swift
//  KlaviyoSwift
//
//  Created by Klaviyo SDK
//

import Foundation
import UserNotifications

/// Predefined push notification action button categories provided by Klaviyo.
/// Similar to Braze's default push categories: Accept/Decline, Yes/No, Confirm/Cancel, and View/Dismiss.
public enum KlaviyoPushCategory: String, CaseIterable {
    /// Category with "Accept" and "Decline" action buttons
    case acceptDecline = "com.klaviyo.category.acceptDecline"

    /// Category with "Yes" and "No" action buttons
    case yesNo = "com.klaviyo.category.yesNo"

    /// Category with "Confirm" and "Cancel" action buttons
    case confirmCancel = "com.klaviyo.category.confirmCancel"

    /// Category with "View" and "Dismiss" action buttons
    case viewDismiss = "com.klaviyo.category.viewDismiss"

    /// The category identifier used in APNs payload
    public var identifier: String {
        rawValue
    }

    /// Creates the UNNotificationCategory for this Klaviyo category
    func createNotificationCategory() -> UNNotificationCategory {
        switch self {
        case .acceptDecline:
            return createAcceptDeclineCategory()
        case .yesNo:
            return createYesNoCategory()
        case .confirmCancel:
            return createConfirmCancelCategory()
        case .viewDismiss:
            return createViewDismissCategory()
        }
    }

    // MARK: - Category Creation

    private func createAcceptDeclineCategory() -> UNNotificationCategory {
        let accept = UNNotificationAction(
            identifier: KlaviyoPushAction.accept.rawValue,
            title: "Accept",
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: KlaviyoPushAction.decline.rawValue,
            title: "Decline",
            options: []
        )

        return UNNotificationCategory(
            identifier: identifier,
            actions: [accept, decline],
            intentIdentifiers: [],
            options: []
        )
    }

    private func createYesNoCategory() -> UNNotificationCategory {
        let yes = UNNotificationAction(
            identifier: KlaviyoPushAction.yes.rawValue,
            title: "Yes",
            options: [.foreground]
        )
        let no = UNNotificationAction(
            identifier: KlaviyoPushAction.no.rawValue,
            title: "No",
            options: []
        )

        return UNNotificationCategory(
            identifier: identifier,
            actions: [yes, no],
            intentIdentifiers: [],
            options: []
        )
    }

    private func createConfirmCancelCategory() -> UNNotificationCategory {
        let confirm = UNNotificationAction(
            identifier: KlaviyoPushAction.confirm.rawValue,
            title: "Confirm",
            options: [.foreground]
        )
        let cancel = UNNotificationAction(
            identifier: KlaviyoPushAction.cancel.rawValue,
            title: "Cancel",
            options: []
        )

        return UNNotificationCategory(
            identifier: identifier,
            actions: [confirm, cancel],
            intentIdentifiers: [],
            options: []
        )
    }

    private func createViewDismissCategory() -> UNNotificationCategory {
        let view = UNNotificationAction(
            identifier: KlaviyoPushAction.view.rawValue,
            title: "View",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: KlaviyoPushAction.dismiss.rawValue,
            title: "Dismiss",
            options: [.destructive]
        )

        return UNNotificationCategory(
            identifier: identifier,
            actions: [view, dismiss],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Action identifiers for Klaviyo push notification buttons
public enum KlaviyoPushAction: String {
    case accept = "com.klaviyo.action.accept"
    case decline = "com.klaviyo.action.decline"
    case yes = "com.klaviyo.action.yes"
    case no = "com.klaviyo.action.no"
    case confirm = "com.klaviyo.action.confirm"
    case cancel = "com.klaviyo.action.cancel"
    case view = "com.klaviyo.action.view"
    case dismiss = "com.klaviyo.action.dismiss"

    /// Check if this action opens the app in foreground
    public var opensForeground: Bool {
        switch self {
        case .accept, .yes, .confirm, .view:
            return true
        case .decline, .no, .cancel, .dismiss:
            return false
        }
    }
}
