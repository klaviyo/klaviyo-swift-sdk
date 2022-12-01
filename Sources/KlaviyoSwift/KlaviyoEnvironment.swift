//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Foundation
import AnyCodable

var environment = KlaviyoEnvironment.production

let PRODUCTION_HOST = "https://a.klaviyo.com"
let encoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

let decoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private var networkSession: NetworkSession!
func createNetworkSession() -> NetworkSession {
    if networkSession == nil {
        networkSession = NetworkSession.production
    }
    return networkSession
}

struct KlaviyoEnvironment {
    var archiverClient: ArchiverClient
    var fileClient: FileClient
    var data: (URL) throws -> Data
    var logger: LoggerClient
    var decodeJSON: (Data) throws -> AnyDecodable
    var analytics: AnalyticsEnvironment
    static let production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        data: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        decodeJSON: { data in try decoder.decode(AnyDecodable.self, from: data) },
        analytics: AnalyticsEnvironment.production
    )
}

struct AnalyticsEnvironment {
    var networkSession: () -> NetworkSession
    var apiURL: String
    var encodeJSON: (Encodable) throws -> Data
    var uuid: () -> UUID
    var date: () -> Date
    var timeZone: () -> String
    var appContextInfo: () -> AppContextInfo
    var engine: AnalyticsEngine
    var klaviyoAPI: KlaviyoAPI
    var store: Store
    var getUserDefaultStringValue: (String) -> String?
    static let production = AnalyticsEnvironment(
        networkSession: createNetworkSession,
        apiURL: PRODUCTION_HOST,
        encodeJSON: { encodable in try encoder.encode(encodable) },
        uuid: { UUID() },
        date: { Date() },
        timeZone: { TimeZone.autoupdatingCurrent.identifier },
        appContextInfo: { AppContextInfo() },
        engine: AnalyticsEngine.production,
        klaviyoAPI: KlaviyoAPI.production,
        store: Store.production,
        getUserDefaultStringValue: { key in UserDefaults.standard.string(forKey: key)}
    )
}
