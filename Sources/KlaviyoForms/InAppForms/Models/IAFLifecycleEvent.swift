//
// IAFLifecycleEvent.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

enum IAFLifecycleEvent {
    case present(withLayout: FormLayout)
    case dismiss
    case abort
    case handShook

    var rawValue: String {
        switch self {
        case .present: return "present"
        case .dismiss: return "dismiss"
        case .abort: return "abort"
        case .handShook: return "handShook"
        }
    }
}
