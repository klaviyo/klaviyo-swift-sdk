//
//  CreateProfilePayload.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation
import KlaviyoSDKDependencies

public struct CreateProfilePayload: Equatable, Codable, Sendable {
    public init(data: ProfilePayload) {
        self.data = data
    }

    public var data: ProfilePayload
}
