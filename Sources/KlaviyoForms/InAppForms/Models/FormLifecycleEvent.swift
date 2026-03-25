//
//  FormLifecycleEvent.swift
//
//
//  Created by Ajay Subramanya on 2026-02-20.
//

import Foundation

/// Events in the lifecycle of an in-app form that can be observed.
///
/// Each case carries the contextual data relevant to that event, including
/// `formId` and `formName` for all events, and CTA-specific fields for
/// ``formCtaClicked``.
///
/// Use these events to track form interactions and send engagement data
/// to third-party analytics platforms.
///
/// Example usage:
/// ```swift
/// KlaviyoSDK().registerFormLifecycleHandler { event in
///     switch event {
///     case .formShown(let formId, let formName):
///         Analytics.track("Form Shown", properties: ["formId": formId ?? ""])
///     case .formDismissed(let formId, let formName):
///         Analytics.track("Form Dismissed", properties: ["formId": formId ?? ""])
///     case .formCtaClicked(let formId, let formName, let buttonLabel, let deepLinkUrl):
///         Analytics.track("Form CTA Clicked", properties: [
///             "formId": formId ?? "",
///             "buttonLabel": buttonLabel ?? ""
///         ])
///     }
/// }
/// ```
public enum FormLifecycleEvent: Equatable, Sendable {
    /// Triggered when a form is about to be presented to the user.
    ///
    /// This event fires after all validation checks pass and immediately
    /// before the form view controller is presented.
    case formShown(formId: String?, formName: String?)

    /// Triggered when a form is dismissed, regardless of the reason.
    ///
    /// This event fires for all dismissal types including:
    /// - User-initiated dismissals (tapping outside, close button)
    /// - Timeout-based dismissals
    /// - Programmatic dismissals
    case formDismissed(formId: String?, formName: String?)

    /// Triggered when a user taps a call-to-action button in a form.
    ///
    /// This event fires before the deep link URL is processed, ensuring
    /// the event is captured even if URL routing fails.
    ///
    /// - `buttonLabel`: The label text of the tapped button, if provided by the form.
    /// - `deepLinkUrl`: The deep link URL associated with the CTA, if configured.
    case formCtaClicked(formId: String?, formName: String?, buttonLabel: String?, deepLinkUrl: URL?)

    /// The unique identifier of the form that triggered this event.
    public var formId: String? {
        switch self {
        case let .formShown(formId, _),
             let .formDismissed(formId, _),
             let .formCtaClicked(formId, _, _, _):
            return formId
        }
    }

    /// The display name of the form that triggered this event.
    public var formName: String? {
        switch self {
        case let .formShown(_, formName),
             let .formDismissed(_, formName),
             let .formCtaClicked(_, formName, _, _):
            return formName
        }
    }

    /// A string identifier for the event type, suitable for logging.
    var eventName: String {
        switch self {
        case .formShown: return "form_shown"
        case .formDismissed: return "form_dismissed"
        case .formCtaClicked: return "form_cta_clicked"
        }
    }
}
