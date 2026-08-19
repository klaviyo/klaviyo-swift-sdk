//
//  UnattributedBuffer.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 8/19/26.
//

import Foundation

/// One request-generating call captured before an apiKey was known. Stored apiKey-free
/// (the apiKey is stamped into the endpoint at drain). Named to echo `UnattributedBuffer`.
enum UnattributedRequest: Codable, Equatable {
    case event(CreateEventPayload, RequestPriority)
    case aggregateEvent(Data)
    case profile(CreateProfilePayload)
    case pushToken(PushTokenPayload)
}

/// Versioned on-disk shape for the buffer file (`klaviyo-unattributed.json`).
struct PersistedUnattributedBuffer: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    var requests: [UnattributedRequest]

    init(version: Int = currentVersion, requests: [UnattributedRequest] = []) {
        self.version = version
        self.requests = requests
    }
}
