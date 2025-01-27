//
//  WebViewConsoleRelayMessage.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 1/27/25.
//

struct WebViewConsoleRelayMessage: Decodable {
    enum ResponseType: Decodable {
        case imagesLoaded
        case documentReady
        case console(ConsoleData)

        struct ConsoleData: Decodable {
            let level: Level
            let message: String

            enum Level: String, Decodable {
                case log
                case warn
                case error
            }
        }

        enum TypeIdentifier: String, Decodable {
            case imagesLoaded
            case documentReady
            case console
        }
    }

    let type: ResponseType

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WebViewConsoleRelayMessage.CodingKeys.self)
        let typeIdentifier = try container.decode(ResponseType.TypeIdentifier.self, forKey: .type)

        switch typeIdentifier {
        case .imagesLoaded:
            type = .imagesLoaded
        case .documentReady:
            type = .documentReady
        case .console:
            let consoleData = try container.decode(ResponseType.ConsoleData.self, forKey: .data)
            type = .console(consoleData)
        }
    }
}

extension WebViewConsoleRelayMessage {
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
}
