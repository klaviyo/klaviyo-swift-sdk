//
//  IAFMessageBusEvent.swift
//  TestApp
//
//  Created by Andrew Balmer on 2/3/25.
//

import AnyCodable
import Foundation

enum IAFMessageBusEvent: Decodable, Equatable {
    // TODO: add associated values with the appropriate data types
    case formsDataLoaded
    case formAppeared
    case trackAggregateEvent(Data)
    case trackProfileEvent(Data)
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
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackAggregateEvent(data)
        case .trackProfileEvent:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackProfileEvent(data)
        case .openDeepLink:
            self = .openDeepLink
        }
    }
}
