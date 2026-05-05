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
    /// Triggered when a form is shown to the user.
    ///
    /// Fired after the SDK has initiated form presentation.
    case formShown(formId: String, formName: String)

    /// Triggered when a form is dismissed by the user.
    ///
    /// Fired after the SDK has initiated form dismissal. Fires for
    /// user-initiated dismissals (e.g. tapping outside, close button).
    /// Does **not** fire when the SDK tears down the form internally
    /// (session timeouts, aborts).
    case formDismissed(formId: String, formName: String)

    /// Triggered when a user taps a call-to-action (CTA) button in a form
    /// that has a deep link URL configured.
    ///
    /// Fired after the SDK has initiated deep link navigation. Not emitted
    /// if no deep link URL is configured for the CTA.
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
