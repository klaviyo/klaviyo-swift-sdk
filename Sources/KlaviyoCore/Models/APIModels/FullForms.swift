//
//  FullForms.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/25/24.
//

import Foundation

public struct FullForms: Equatable {
    public let forms: [Data]
    public let formSettings: Data
    public let dynamicInfoConfig: Data?

    private enum CodingKeys: String, CodingKey {
        case forms = "full_forms"
        case formSettings = "form_settings"
        case dynamicInfoConfig = "dynamic_info_config"
    }

    public init(data: Data) throws {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KlaviyoDecodingError.invalidType
        }

        let fullFormsObject: [[String: Any]] = try jsonObject.value(forKey: CodingKeys.forms.rawValue)
        forms = try fullFormsObject.map {
            let data = try JSONSerialization.data(withJSONObject: $0)
            return data
        }

        let formSettingsObject: [String: Any] = try jsonObject.value(forKey: CodingKeys.formSettings.rawValue)
        let formSettingsData = try JSONSerialization.data(withJSONObject: formSettingsObject)
        formSettings = formSettingsData

        let dynamicInfoConfigObject: [String: Any] = try jsonObject.value(forKey: CodingKeys.dynamicInfoConfig.rawValue)
        if !dynamicInfoConfigObject.isEmpty {
            let dynamicInfoConfigData = try JSONSerialization.data(withJSONObject: dynamicInfoConfigObject)
            dynamicInfoConfig = dynamicInfoConfigData
        } else {
            dynamicInfoConfig = nil
        }
    }
}
