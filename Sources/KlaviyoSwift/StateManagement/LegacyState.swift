//
//  LegacyState.swift
//  klaviyo-swift-sdk
//
//  Codable DTO for the pre-split legacy `klaviyo-{apiKey}-state.json` blob. Owned by the
//  migration; decoupled from the runtime `KlaviyoState` so that type can be non-Codable.
//

import Foundation
import KlaviyoCore

struct LegacyState: Codable, Equatable {
    var apiKey: String?
    var identity: ProfileData
    var pushTokenData: PushTokenData?
    var queue: [KlaviyoRequest]

    private enum CodingKeys: CodingKey { case apiKey, identity, queue, pushTokenData }
    private enum LegacyCodingKeys: CodingKey { case email, anonymousId, phoneNumber, externalId }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        pushTokenData = try container.decodeIfPresent(PushTokenData.self, forKey: .pushTokenData)
        queue = try container.decodeIfPresent([KlaviyoRequest].self, forKey: .queue) ?? []

        if let identity = try container.decodeIfPresent(ProfileData.self, forKey: .identity) {
            self.identity = identity
        } else if let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self) {
            identity = try ProfileData(
                email: legacy.decodeIfPresent(String.self, forKey: .email),
                phoneNumber: legacy.decodeIfPresent(String.self, forKey: .phoneNumber),
                externalId: legacy.decodeIfPresent(String.self, forKey: .externalId),
                anonymousId: legacy.decodeIfPresent(String.self, forKey: .anonymousId)
            )
        } else {
            identity = ProfileData()
        }
    }
}
