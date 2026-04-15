//
//  IAFLifecycleEvent.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/11/25.
//

enum IAFLifecycleEvent {
    case present(formId: String?, formName: String?, withLayout: FormLayout)
    case dismiss(formId: String?, formName: String?)
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
