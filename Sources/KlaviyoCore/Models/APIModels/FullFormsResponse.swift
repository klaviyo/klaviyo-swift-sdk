//
//  FullFormsResponse.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/25/24.
//

import Foundation

public struct FullFormsResponse: Codable, Equatable {
    public let fullForms: [FullForm]
    public let formSettings: FormSettings
    public let dynamicInfoConfig: DynamicInfoConfig?

    enum CodingKeys: String, CodingKey {
        case fullForms = "full_forms"
        case formSettings = "form_settings"
        case dynamicInfoConfig = "dynamic_info_config"
    }
}

extension FullFormsResponse {
    public struct FullForm: Codable, Equatable {
        // TODO: determine which properties we need to decode
    }
}

extension FullFormsResponse {
    public struct FormSettings: Codable, Equatable {
        // TODO: determine which properties we need to decode
    }
}

extension FullFormsResponse {
    public struct DynamicInfoConfig: Codable, Equatable {
        // TODO: determine which properties we need to decode
    }
}
