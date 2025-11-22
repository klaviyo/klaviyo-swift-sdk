//
//  PushCategoryRegistration.swift
//
//
//  Created by Ajay Subramanya on 11/21/24.
//

import Foundation
import OSLog
import UserNotifications

/// Configuration option for registering push notification categories
public enum CategoryRegistrationOption {
    /// Automatically register all predefined Klaviyo categories
    case automatic

    /// Manually register specific categories
    case manual(KlaviyoPushCategory...)
}

extension KlaviyoSDK {
    /// Registers Klaviyo's predefined push notification categories with action buttons.
    ///
    /// This method follows the same pattern as Braze - developers must explicitly register
    /// the categories they want to use. The categories define which action buttons appear
    /// on push notifications.
    ///
    /// This method intelligently merges with any existing categories already registered,
    /// so it won't overwrite your custom categories.
    ///
    /// ## Example Usage
    ///
    /// Register all predefined categories automatically:
    /// ```swift
    /// KlaviyoSDK().registerPushCategories(.automatic)
    /// ```
    ///
    /// Register specific categories manually:
    /// ```swift
    /// KlaviyoSDK().registerPushCategories(.manual(.acceptDecline, .yesNo))
    /// ```
    ///
    /// ## APNs Payload
    ///
    /// To use these categories, your push notification payload should include the category identifier:
    /// ```json
    /// {
    ///   "aps": {
    ///     "alert": "Your order has shipped!",
    ///     "category": "com.klaviyo.category.viewDismiss"
    ///   },
    ///   "body": {
    ///     "_k": "...",
    ///     "actions": {
    ///       "com.klaviyo.action.view": {
    ///         "url": "myapp://orders/12345"
    ///       },
    ///       "com.klaviyo.action.dismiss": {}
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// ## Action Handling
    ///
    /// The SDK automatically:
    /// - Tracks action button taps as events
    /// - Opens URLs/deep links from the action metadata
    /// - Maintains backwards compatibility with regular push taps
    ///
    /// - Parameter option: Registration option - either automatic (all categories) or manual (specific categories)
    public func registerPushCategories(_ option: CategoryRegistrationOption) {
        let categories: Set<KlaviyoPushCategory>

        switch option {
        case .automatic:
            categories = Set(KlaviyoPushCategory.allCases)
        case let .manual(selectedCategories):
            categories = Set(selectedCategories)
        }

        // Create UNNotificationCategory instances from Klaviyo categories
        let klaviyoCategories = Set(categories.map { $0.createNotificationCategory() })

        // Get existing categories and merge intelligently
        UNUserNotificationCenter.current().getNotificationCategories { existingCategories in
            let mergedCategories = self.mergeCategories(
                existing: existingCategories,
                new: klaviyoCategories
            )

            // Register the merged set
            UNUserNotificationCenter.current().setNotificationCategories(mergedCategories)

            if #available(iOS 14.0, *) {
                Logger.notifications.info("Registered \(categories.count) Klaviyo push categories")
            }
        }
    }

    /// Merges existing notification categories with new Klaviyo categories.
    /// If a category with the same identifier exists, the existing one is kept (not overwritten).
    private func mergeCategories(
        existing: Set<UNNotificationCategory>,
        new: Set<UNNotificationCategory>
    ) -> Set<UNNotificationCategory> {
        var merged = existing

        for newCategory in new {
            // Only add if identifier doesn't already exist
            if !existing.contains(where: { $0.identifier == newCategory.identifier }) {
                merged.insert(newCategory)
            } else {
                if #available(iOS 14.0, *) {
                    Logger.notifications.debug(
                        "Category '\(newCategory.identifier)' already exists, skipping"
                    )
                }
            }
        }

        return merged
    }
}
