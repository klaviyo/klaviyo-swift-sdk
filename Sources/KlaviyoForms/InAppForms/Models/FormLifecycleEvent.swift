//
//  FormLifecycleEvent.swift
//
//
//  Created by Ajay Subramanya on 2026-02-20.
//

import Foundation

/// Events in the lifecycle of an in-app form that can be observed.
///
/// Use these events to track form interactions and send engagement data
/// to third-party analytics platforms.
///
/// Example usage:
/// ```swift
/// KlaviyoSDK().registerFormLifecycleHandler { event, context in
///     switch event {
///     case .formShown:
///         Analytics.track("Form Shown", properties: ["formId": context.formId ?? ""])
///     case .formDismissed:
///         Analytics.track("Form Dismissed", properties: ["formId": context.formId ?? ""])
///     case .formCTAClicked:
///         Analytics.track("Form CTA Clicked", properties: ["formId": context.formId ?? ""])
///     }
/// }
/// ```
public enum FormLifecycleEvent: String, Equatable, Sendable {
    /// Triggered when a form is about to be presented to the user.
    ///
    /// This event fires after all validation checks pass and immediately
    /// before the form view controller is presented.
    case formShown = "form_shown"

    /// Triggered when a form is dismissed, regardless of the reason.
    ///
    /// This event fires for all dismissal types including:
    /// - User-initiated dismissals (tapping outside, close button)
    /// - Timeout-based dismissals
    /// - Programmatic dismissals
    case formDismissed = "form_dismissed"

    /// Triggered when a user taps a call-to-action button in a form.
    ///
    /// This event fires before the deep link URL is processed, ensuring
    /// the event is captured even if URL routing fails.
    case formCTAClicked = "form_cta_clicked"
}
