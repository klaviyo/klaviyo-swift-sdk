//
//  InboxChangeSignal.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 11/4/26.
//

import Foundation

/// Tells every process sharing the Inbox store that it changed. The signal carries no data: a listener
/// refetches whatever it is showing.
package protocol InboxChangeSignaling: Sendable {
    func post()
}
