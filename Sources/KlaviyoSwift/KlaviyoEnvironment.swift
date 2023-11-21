//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import AnyCodable
import Combine
import Foundation
import UIKit

var environment = KlaviyoEnvironment.production

struct KlaviyoEnvironment {
    fileprivate static let productionHost = "https://a.klaviyo.com"
    static let encoder = { () -> JSONEncoder in
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder = { () -> JSONDecoder in
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let reachabilityService = Reachability(hostname: URL(string: productionHost)!.host!)

    var archiverClient: ArchiverClient
    var fileClient: FileClient
    var data: (URL) throws -> Data
    var logger: LoggerClient
    var analytics: AnalyticsEnvironment
    var getUserDefaultString: (String) -> String?
    var appLifeCycle: AppLifeCycleEvents
    var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    var getNotificationSettings: (@escaping (KlaviyoState.PushEnablement) -> Void) -> Void
    var getBackgroundSetting: () -> KlaviyoState.PushBackground
    var legacyIdentifier: () -> String
    var startReachability: () throws -> Void
    var stopReachability: () -> Void
    var reachabilityStatus: () -> Reachability.NetworkStatus?
    var randomInt: () -> Int
    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    var raiseFatalError: (String) -> Void
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
        getNotificationSettings: { callback in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                callback(.create(from: settings.authorizationStatus))
            }
        },
        getBackgroundSetting: { .create(from: UIApplication.shared.backgroundRefreshStatus) },
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
        stateChangePublisher: StateChangePublisher().publisher, raiseFatalError: { msg in
            #if DEBUG
            fatalError(msg)
            #endif
        })
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
        try jsonDecoder.decode(T.self, from: data)
    }

    var jsonDecoder: JSONDecoder
    static let production = Self(jsonDecoder: KlaviyoEnvironment.decoder)
}

struct AnalyticsEnvironment {
    var networkSession: () -> NetworkSession
    var apiURL: String
    var encodeJSON: (AnyEncodable) throws -> Data
    var decoder: DataDecoder
    var uuid: () -> UUID
    var date: () -> Date
    var timeZone: () -> String
    var appContextInfo: () -> AppContextInfo
    var klaviyoAPI: KlaviyoAPI
    var timer: (Double) -> AnyPublisher<Date, Never>
    var send: (KlaviyoAction) -> Task<Void, Never>?
    var state: () -> KlaviyoState
    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    static let production: AnalyticsEnvironment = {
        let store = Store.production
        return AnalyticsEnvironment(
            networkSession: createNetworkSession,
            apiURL: KlaviyoEnvironment.productionHost,
            encodeJSON: { encodable in try KlaviyoEnvironment.encoder.encode(encodable) },
            decoder: DataDecoder.production,
            uuid: { UUID() },
            date: { Date() },
            timeZone: { TimeZone.autoupdatingCurrent.identifier },
            appContextInfo: { AppContextInfo() },
            klaviyoAPI: KlaviyoAPI(),
            timer: { interval in
                Timer.publish(every: interval, on: .main, in: .default)
                    .autoconnect()
                    .eraseToAnyPublisher()
            },
            send: { action in
                store.send(action)
            },
            state: { store.state.value },
            statePublisher: { store.state.eraseToAnyPublisher() })
    }()
}
