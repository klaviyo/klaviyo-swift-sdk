//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Foundation
import AnyCodable
import Combine
import UIKit

var environment = KlaviyoEnvironment.production

let PRODUCTION_HOST = "https://a.klaviyo.com"
let encoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

let decoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

// TODO: use hostname based on api url instead of hard coding
private let reachabilityService = Reachability(hostname: "a.klaviyo.com")

struct KlaviyoEnvironment {
    var archiverClient: ArchiverClient
    var fileClient: FileClient
    var data: (URL) throws -> Data
    var logger: LoggerClient
    var analytics: AnalyticsEnvironment
    var getUserDefaultString: (String) -> String?
    var appLifeCycle: AppLifeCycleEvents
    var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    var legacyIdentifier: () -> String
    var startReachability: () throws -> Void
    var stopReachability: () -> Void
    var reachabilityStatus: () -> Reachability.NetworkStatus?
    var randomInt: () -> Int
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    static var production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        data: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        analytics: AnalyticsEnvironment.production,
        getUserDefaultString: { key in UserDefaults.standard.string(forKey: key) },
        appLifeCycle: AppLifeCycleEvents.production,
        notificationCenterPublisher: { name in
            NotificationCenter.default.publisher(for: name)
                .eraseToAnyPublisher()
        },
        legacyIdentifier: { "iOS:\(UIDevice.current.identifierForVendor!.uuidString)" },
        startReachability: {
            try reachabilityService?.startNotifier()
        },
        stopReachability: {
            reachabilityService?.stopNotifier()
        },
        reachabilityStatus: {
            reachabilityService?.currentReachabilityStatus
        },
        randomInt: { Int.random(in: 0...10) },
        stateChangePublisher: StateChangePublisher().publisher
    )
}

private var networkSession: NetworkSession!
func createNetworkSession() -> NetworkSession {
    if networkSession == nil {
        networkSession = NetworkSession.production
    }
    return networkSession
}



enum KlaviyoDecodingError: Error {
    case invalidType
}

struct DataDecoder {
    func decode<T: Decodable>(_ data: Data) throws -> T {
        return try jsonDecoder.decode(T.self, from: data)
    }
    var jsonDecoder: JSONDecoder
    static let production = Self(jsonDecoder: decoder)
}

struct AnalyticsEnvironment {
    var networkSession: () -> NetworkSession
    var apiURL: String
    var encodeJSON: (Encodable) throws -> Data
    var decoder: DataDecoder
    var uuid: () -> UUID
    var date: () -> Date
    var timeZone: () -> String
    var appContextInfo: () -> AppContextInfo
    var klaviyoAPI: KlaviyoAPI
    var store: Store<KlaviyoState, KlaviyoAction>
    var timer: (Double) -> AnyPublisher<Date, Never>
    static let production = AnalyticsEnvironment(
        networkSession: createNetworkSession,
        apiURL: PRODUCTION_HOST,
        encodeJSON: { encodable in try encoder.encode(encodable) },
        decoder: DataDecoder.production,
        uuid: { UUID() },
        date: { Date() },
        timeZone: { TimeZone.autoupdatingCurrent.identifier },
        appContextInfo: { AppContextInfo() },
        klaviyoAPI: KlaviyoAPI(),
        store: Store.production,
        timer: { interval in
            Timer.publish(every: interval, on: .main, in: .default)
            .autoconnect()
            .eraseToAnyPublisher()
        }
    )
}
