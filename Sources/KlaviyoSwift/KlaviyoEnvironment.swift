//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Foundation

var environment = KlaviyoEnvironment.production

let PRODUCTION_HOST = "https://a.klaviyo.com"
let encoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

struct KlaviyoEnvironment {
    var archiverClient: ArchiverClient
    var fileClient: FileClient
    var data: (URL) throws -> Data
    var logger: LoggerClient
    var networkSession: NetworkSession
    var apiURL: String
    var encodeJSON: (Encodable) throws -> Data
    static let production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        data: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        networkSession: NetworkSession.production,
        apiURL: PRODUCTION_HOST,
        encodeJSON: { encodable in try encoder.encode(encodable) }
    )
}
