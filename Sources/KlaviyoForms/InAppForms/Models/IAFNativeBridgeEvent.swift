//
//  IAFNativeBridgeEvent.swift
//  TestApp
//
//  Created by Andrew Balmer on 2/3/25.
//

import AnyCodable
import Foundation
import OSLog

enum IAFNativeBridgeEvent: Decodable, Equatable {
    case formsDataLoaded
    case formWillAppear(Data)
    case formDisappeared
    case trackProfileEvent(Data)
    case trackAggregateEvent(Data)
    case openDeepLink(URL)
    case abort(String)
    case handShook
    case analyticsEvent
    case lifecycleEvent
    case profileEvent
    case profileMutation

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum TypeIdentifier: String, Decodable {
        case formsDataLoaded
        case formWillAppear
        case formDisappeared
        case trackProfileEvent
        case trackAggregateEvent
        case openDeepLink
        case abort
        case handShook
        case analyticsEvent
        case lifecycleEvent
        case profileEvent
        case profileMutation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeIdentifier = try container.decode(TypeIdentifier.self, forKey: .type)

        switch typeIdentifier {
        case .formsDataLoaded:
            self = .formsDataLoaded
        case .formWillAppear:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .formWillAppear(data)
        case .formDisappeared:
            self = .formDisappeared
        case .trackProfileEvent:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackProfileEvent(data)
        case .trackAggregateEvent:
            let decodedData = try container.decode(AnyCodable.self, forKey: .data)
            let data = try JSONEncoder().encode(decodedData)
            self = .trackAggregateEvent(data)
        case .openDeepLink:
            let url = try container.decode(DeepLinkEventPayload.self, forKey: .data)
            self = .openDeepLink(url.ios)
        case .abort:
            let data = try container.decode(AbortPayload.self, forKey: .data)
            self = .abort(data.reason)
        case .handShook:
            self = .handShook
        case .analyticsEvent:
            self = .analyticsEvent
        case .lifecycleEvent:
            self = .lifecycleEvent
        case .profileEvent:
            self = .profileEvent
        case .profileMutation:
            self = .profileMutation
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

extension IAFNativeBridgeEvent {
    public static var handshake: String {
        struct HandshakeData: Codable {
            var type: String
            var version: Int
        }

        let handshakeArray = handshakeEvents.map { event -> HandshakeData in
            HandshakeData(type: event.name, version: event.version)
        }

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(handshakeArray)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error encoding handshake data: \(error)")
            }
        }
        return ""
    }

    private static var handshakeEvents: [IAFNativeBridgeEvent] {
        // events that JS is permitted to sending
        [
            .formWillAppear(Data()),
            .formDisappeared,
            .trackProfileEvent(Data()),
            .trackAggregateEvent(Data()),
            .openDeepLink(URL(string: "https://example.com")!),
            .abort(""),
            .lifecycleEvent,
            .profileEvent,
            .profileMutation
        ]
    }

    private var version: Int {
        switch self {
        case .formsDataLoaded: return 1
        case .formWillAppear: return 2
        case .formDisappeared: return 1
        case .trackProfileEvent: return 1
        case .trackAggregateEvent: return 1
        case .openDeepLink: return 2
        case .abort: return 1
        case .handShook: return 1
        case .analyticsEvent: return 1
        case .lifecycleEvent: return 1
        case .profileEvent: return 1
        case .profileMutation: return 1
        }
    }

    private var name: String {
        switch self {
        case .formsDataLoaded: return "formsDataLoaded"
        case .formWillAppear: return "formWillAppear"
        case .formDisappeared: return "formDisappeared"
        case .trackProfileEvent: return "trackProfileEvent"
        case .trackAggregateEvent: return "trackAggregateEvent"
        case .openDeepLink: return "openDeepLink"
        case .abort: return "abort"
        case .handShook: return "handShook"
        case .analyticsEvent: return "analyticsEvent"
        case .lifecycleEvent: return "lifecycleEvent"
        case .profileEvent: return "profileEvent"
        case .profileMutation: return "profileMutation"
        }
    }
}
