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
///         Analytics.track("Form Shown", properties: ["formId": formId])
///     case .formDismissed(let formId, let formName):
///         Analytics.track("Form Dismissed", properties: ["formId": formId])
///     case .formCtaClicked(let formId, let formName, let buttonLabel, let deepLinkUrl):
///         Analytics.track("Form CTA Clicked", properties: [
///             "formId": formId,
///             "buttonLabel": buttonLabel
///         ])
///     }
/// }
/// ```
public enum FormLifecycleEvent: Equatable, Sendable {
    /// Triggered when the JavaScript bridge reports a form will appear.
    ///
    /// This event reflects the JS-side `formWillAppear` signal and fires
    /// before native presentation validation (e.g. checking for a visible
    /// view controller). In practice, it reliably indicates the form was
    /// shown and matches the analytics data tracked by the webview.
    case formShown(formId: String, formName: String)

    /// Triggered when the JavaScript bridge reports a form has disappeared.
    ///
    /// This event reflects the JS-side `formDisappeared` signal and fires
    /// for user-initiated dismissals (e.g. tapping outside, close button).
    /// It does **not** fire for scenarios where the webview is destroyed
    /// before a form is ever shown, such as session timeouts or aborts.
    case formDismissed(formId: String, formName: String)

    /// Triggered when a user taps a call-to-action button in a form
    /// that has a deep link URL configured.
    ///
    /// This event fires before the deep link URL is processed, ensuring
    /// the event is captured even if URL routing fails. If no deep link
    /// URL is configured for the CTA, this event is not emitted.
    ///
    /// - `buttonLabel`: The label text of the tapped button.
    /// - `deepLinkUrl`: The deep link URL associated with the CTA.
    case formCtaClicked(formId: String, formName: String, buttonLabel: String, deepLinkUrl: URL)

    /// The unique identifier of the form that triggered this event.
    public var formId: String {
        switch self {
        case let .formShown(formId, _),
             let .formDismissed(formId, _),
             let .formCtaClicked(formId, _, _, _):
            return formId
        }
    }

    /// The display name of the form that triggered this event.
    public var formName: String {
        switch self {
        case let .formShown(_, formName),
             let .formDismissed(_, formName),
             let .formCtaClicked(_, formName, _, _):
            return formName
        }
    }

    /// A string identifier for the event type, suitable for logging.
    public var eventName: String {
        switch self {
        case .formShown: return "formShown"
        case .formDismissed: return "formDismissed"
        case .formCtaClicked: return "formCtaClicked"
        }
    }
}
