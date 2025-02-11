//
//  IAFNativeBridgeEvent.swift
//  TestApp
//
//  Created by Andrew Balmer on 2/3/25.
//

import AnyCodable
import Foundation

enum IAFNativeBridgeEvent: Decodable, Equatable {
    // TODO: add associated values with the appropriate data types
    case formsDataLoaded
    case formWillAppear
    case trackAggregateEvent(Data)
    case trackProfileEvent(Data)
    case openDeepLink(URL)
    case formDisappeared
    case abort(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum TypeIdentifier: String, Decodable {
        case formsDataLoaded
        case formWillAppear
        case trackAggregateEvent
        case trackProfileEvent
        case openDeepLink
        case formDisappeared
        case abort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeIdentifier = try container.decode(TypeIdentifier.self, forKey: .type)

        switch typeIdentifier {
        case .formsDataLoaded:
            self = .formsDataLoaded
        case .formWillAppear:
            self = .formWillAppear
        case .trackAggregateEvent:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackAggregateEvent(data)
        case .trackProfileEvent:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackProfileEvent(data)
        case .openDeepLink:
            let url = try container.decode(DeepLinkEventPayload.self, forKey: .data)
            self = .openDeepLink(url.ios)
        case .formDisappeared:
            self = .formDisappeared
        case .abort:
            let data = try container.decode(AbortPayload.self, forKey: .data)
            self = .abort(data.reason)
        }
    }
}

extension IAFNativeBridgeEvent {
    struct DeepLinkEventPayload: Codable {
        let ios: URL
    }

    struct AbortPayload: Codable {
        let reason: String
    }
}
