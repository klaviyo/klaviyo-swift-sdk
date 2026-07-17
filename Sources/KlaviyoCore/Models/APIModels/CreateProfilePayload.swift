//
// CreateProfilePayload.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

public struct CreateProfilePayload: Equatable, Codable {
    public init(data: ProfilePayload) {
        self.data = data
    }

    public var data: ProfilePayload
}
