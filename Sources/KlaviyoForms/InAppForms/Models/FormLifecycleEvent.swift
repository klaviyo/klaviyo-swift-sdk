//
//  FormLifecycleEvent.swift
//
//
//  Created by Ajay Subramanya on 2026-02-20.
//

import Foundation

/// A thread-safe continuation for responding to a form display query.
///
/// Call ``accept()`` to allow the form to display, or ``reject()`` to block it.
/// Only the first call takes effect; subsequent calls are ignored.
///
/// If neither is called within the SDK's timeout window, the form will be
/// allowed to display (fail-open behavior).
public final class FormDisplayContinuation: @unchecked Sendable {
    private let callback: (Bool) -> Void
    private let lock = NSLock()
    private var responded = false

    init(callback: @escaping (Bool) -> Void) {
        self.callback = callback
    }

    /// Allow the form to display.
    public func accept() {
        respond(allowed: true)
    }

    /// Block the form from displaying.
    public func reject() {
        respond(allowed: false)
    }

    /// Whether a response has already been sent.
    var hasResponded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return responded
    }

    @discardableResult
    private func respond(allowed: Bool) -> Bool {
        lock.lock()
        let alreadyResponded = responded
        if !alreadyResponded { responded = true }
        lock.unlock()
        guard !alreadyResponded else { return false }
        callback(allowed)
        return true
    }
}

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
///     case .formWillDisplay(let formId, let formName, let formType, let continuation):
///         if shouldBlockForm(formId) {
///             continuation.reject()
///         } else {
///             continuation.accept()
///         }
///     }
/// }
/// ```
public enum FormLifecycleEvent: Sendable {
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
    /// that has a URL configured — either an in-app deep link or a supported
    /// external/system URL (`http(s)`, `mailto:`, `tel:`, `sms:`).
    ///
    /// Fired after the SDK has initiated navigation (deep link routing, or
    /// opening the URL externally). Not emitted if no URL is configured for
    /// the CTA.
    ///
    /// - `buttonLabel`: The label text of the tapped button.
    /// - `deepLinkUrl`: The URL associated with the CTA. For historical reasons
    ///   this parameter is named `deepLinkUrl`, but it also carries external/
    ///   system URLs.
    case formCtaClicked(formId: String, formName: String, buttonLabel: String, deepLinkUrl: URL)

    /// Triggered when a form is about to be displayed, allowing the host app
    /// to accept or reject the display.
    ///
    /// Call ``FormDisplayContinuation/accept()`` to allow the form to display,
    /// or ``FormDisplayContinuation/reject()`` to block it.
    /// If neither is called within the SDK's timeout window, the form will be
    /// allowed to display (fail-open behavior).
    ///
    /// - `formType`: The type of form (e.g. "POPUP", "FLYOUT", "FULLSCREEN").
    /// - `continuation`: The continuation to call with the accept/reject decision.
    case formWillDisplay(
        formId: String, formName: String, formType: String, continuation: FormDisplayContinuation
    )

    /// The unique identifier of the form that triggered this event.
    public var formId: String {
        switch self {
        case let .formShown(formId, _),
             let .formDismissed(formId, _),
             let .formCtaClicked(formId, _, _, _),
             let .formWillDisplay(formId, _, _, _):
            return formId
        }
    }

    /// The display name of the form that triggered this event.
    public var formName: String {
        switch self {
        case let .formShown(_, formName),
             let .formDismissed(_, formName),
             let .formCtaClicked(_, formName, _, _),
             let .formWillDisplay(_, formName, _, _):
            return formName
        }
    }

    /// A string identifier for the event type, suitable for logging.
    public var eventName: String {
        switch self {
        case .formShown: return "formShown"
        case .formDismissed: return "formDismissed"
        case .formCtaClicked: return "formCtaClicked"
        case .formWillDisplay: return "formWillDisplay"
        }
    }
}

/// Compares event metadata, excluding the display continuation.
extension FormLifecycleEvent: Equatable {
    public static func ==(left: FormLifecycleEvent, right: FormLifecycleEvent) -> Bool {
        switch (left, right) {
        case let (.formShown(leftId, leftName), .formShown(rightId, rightName)):
            return leftId == rightId && leftName == rightName
        case let (.formDismissed(leftId, leftName), .formDismissed(rightId, rightName)):
            return leftId == rightId && leftName == rightName
        case let (.formCtaClicked(leftId, leftName, leftLabel, leftUrl),
                  .formCtaClicked(rightId, rightName, rightLabel, rightUrl)):
            return leftId == rightId && leftName == rightName
                && leftLabel == rightLabel && leftUrl == rightUrl
        case let (.formWillDisplay(leftId, leftName, leftType, _),
                  .formWillDisplay(rightId, rightName, rightType, _)):
            return leftId == rightId && leftName == rightName && leftType == rightType
        default:
            return false
        }
    }
}
