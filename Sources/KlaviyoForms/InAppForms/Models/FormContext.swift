//
//  FormContext.swift
//  klaviyo-swift-sdk
//

import Foundation

/// Contextual information about the in-app form that triggered a lifecycle event.
///
/// This type is passed alongside every ``FormLifecycleEvent`` and carries
/// metadata about the form. New fields may be added in future releases without
/// changing the callback signature.
public struct FormContext: Sendable {
    /// The unique identifier of the form.
    public let formId: String?

    init(formId: String?) {
        self.formId = formId
    }
}
