//
//  InboxProfileResetHandler.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/16/26.
//

import Foundation
import KlaviyoCore
import KlaviyoInboxCore
import OSLog

/// Clears the inbox when the app resets the profile, so one profile's messages are never shown to the
/// next. `KlaviyoSwift` finds this class by its Objective-C name, which must match
/// ``ProfileResetNotifier/inboxHandlerClassName``.
@objc(KlaviyoInboxProfileResetHandler)
final class InboxProfileResetHandler: NSObject, ProfileResetHandling {
    private let clearAll: @Sendable () async throws -> Void

    override convenience init() {
        self.init(clearAll: { try await InboxStore.shared.clearAll() })
    }

    init(clearAll: @escaping @Sendable () async throws -> Void) {
        self.clearAll = clearAll
        super.init()
    }

    func profileDidReset() {
        let clearAll = clearAll
        Task.detached {
            do {
                try await clearAll()
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.mobileInbox.error("Could not clear the inbox on profile reset.")
                }
            }
        }
    }
}
