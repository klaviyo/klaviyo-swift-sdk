//
//  ProfileResetHandling.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

import Foundation

/// Implemented by a feature module that must drop per-profile data when the app resets the profile.
///
/// `KlaviyoSwift` cannot depend on feature modules, so it finds a handler by class name at runtime, the
/// way the automatic push bootstrap finds its installer. A module opts in by exposing a class with
/// the name in ``ProfileResetNotifier/inboxHandlerClassName`` that has a no-argument initializer.
public protocol ProfileResetHandling: AnyObject {
    func profileDidReset()
}

public enum ProfileResetNotifier {
    /// The Objective-C name of the Mobile Inbox's handler. `KlaviyoInbox` must publish its handler under
    /// this exact name.
    public static let inboxHandlerClassName = "KlaviyoInboxProfileResetHandler"

    /// Tells every feature module that is linked into the app that the profile was reset. A module that
    /// is not linked has nothing to clear and is skipped.
    public static func notify() {
        for name in [inboxHandlerClassName] {
            guard let handlerClass = NSClassFromString(name) as? NSObject.Type,
                  let handler = handlerClass.init() as? ProfileResetHandling else { continue }
            handler.profileDidReset()
        }
    }
}
