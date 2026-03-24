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

    /// The display name of the form.
    public let formName: String?

    /// The deep link URL that was opened. Only populated for ``FormLifecycleEvent/formCTAClicked`` events.
    public let deepLinkUrl: URL?

    /// The label text of the button that was tapped. Only populated for ``FormLifecycleEvent/formCTAClicked`` events.
    public let buttonLabel: String?

    public init(formId: String?, formName: String?, deepLinkUrl: URL? = nil, buttonLabel: String? = nil) {
        self.formId = formId
        self.formName = formName
        self.deepLinkUrl = deepLinkUrl
        self.buttonLabel = buttonLabel
    }
}
