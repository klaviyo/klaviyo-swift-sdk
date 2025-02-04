//
//  CreateProfilePayload.swift
//
//
//  Created by Ajay Subramanya on 8/5/24.
//

import Foundation

public struct CreateProfilePayload: Equatable, Codable {
    public init(data: ProfilePayload) {
        self.data = data
    }

    public var data: ProfilePayload
}
