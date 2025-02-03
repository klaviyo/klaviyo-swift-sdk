//
//  IAFMessageBusEvent.swift
//  TestApp
//
//  Created by Andrew Balmer on 2/3/25.
//

import Foundation

enum IAFMessageBusEvent: Decodable {
    case formsDataLoaded
    case formAppeared
    case trackAggregateEvent(Data)
    case trackProfileEvent
    case openDeepLink

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum TypeIdentifier: String, Decodable {
        case formsDataLoaded
        case formAppeared
        case trackAggregateEvent
        case trackProfileEvent
        case openDeepLink
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeIdentifier = try container.decode(TypeIdentifier.self, forKey: .type)

        switch typeIdentifier {
        case .formsDataLoaded:
            self = .formsDataLoaded
        case .formAppeared:
            self = .formAppeared
        case .trackAggregateEvent:
            let dataContainer = try container.decode([String: AnyCodable].self, forKey: .data)
            let data = try JSONSerialization.data(withJSONObject: dataContainer)
            self = .trackAggregateEvent(data)
        case .trackProfileEvent:
            self = .trackProfileEvent
        case .openDeepLink:
            self = .openDeepLink
        }
    }
}

// Since Swift’s Codable system doesn’t allow direct decoding into [String: Any],
// we need an intermediate AnyCodable type:
private struct AnyCodable: Codable {}
