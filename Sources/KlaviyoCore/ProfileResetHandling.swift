//
//  ProfileResetHandling.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

import Foundation

/// Implemented by anything that needs to know when the profile is reset, so it can drop per-profile data.
public protocol ProfileResetHandling: AnyObject {
    func profileDidReset()
}

/// Notifies the registered ``ProfileResetHandling`` types that the profile was reset.
///
/// Handlers are found by Objective-C class name, so the notifier does not depend on the modules that
/// provide them. A handler needs a no-argument initializer, and one that is not linked is skipped.
public enum ProfileResetNotifier {
    /// The Objective-C name the Mobile Inbox publishes its handler under.
    public static let inboxHandlerClassName = "KlaviyoInboxProfileResetHandler"

    /// Calls ``ProfileResetHandling/profileDidReset()`` on each handler that is present.
    public static func notify() {
        for name in [inboxHandlerClassName] {
            guard let handlerClass = NSClassFromString(name) as? NSObject.Type,
                  let handler = handlerClass.init() as? ProfileResetHandling else { continue }
            handler.profileDidReset()
        }
    }
}
