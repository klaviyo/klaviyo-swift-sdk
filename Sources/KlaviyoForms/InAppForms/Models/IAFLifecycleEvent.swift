//
//  IAFLifecycleEvent.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/11/25.
//

enum IAFLifecycleEvent {
    case presentWithLayout(FormLayout)
    case dismiss
    case abort
    case handShook
}
