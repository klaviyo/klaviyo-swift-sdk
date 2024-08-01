//
//  File.swift
//
//
//  Created by Ajay Subramanya on 7/18/24.
//

import AnyCodable
import Combine
import Foundation
import UIKit

public var environment = KlaviyoEnvironment.production

public struct KlaviyoEnvironment {
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
    public var fileClient: FileClient
    public var data: (URL) throws -> Data
    public var logger: LoggerClient
    public var analytics: AnalyticsEnvironment
    var getUserDefaultString: (String) -> String?
    // TODO: update this to remove klaviyo action and return something more generic and have the state management handle mapping that to KlaviyoAction
//    var appLifeCycle: AppLifeCycleEvents
    var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    var getNotificationSettings: (@escaping (PushEnablement) -> Void) -> Void
    var getBackgroundSetting: () -> PushBackground
    var legacyIdentifier: () -> String
    var startReachability: () throws -> Void
    var stopReachability: () -> Void
    var reachabilityStatus: () -> Reachability.NetworkStatus?
    public var randomInt: () -> Int
//    var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    public var raiseFatalError: (String) -> Void
    public var emitDeveloperWarning: (String) -> Void
    static var production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        data: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        analytics: AnalyticsEnvironment.production,
        getUserDefaultString: { key in UserDefaults.standard.string(forKey: key) },
//        appLifeCycle: AppLifeCycleEvents.production,
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
//        stateChangePublisher: StateChangePublisher().publisher,
        raiseFatalError: { msg in
            #if DEBUG
            fatalError(msg)
            #endif
        },
        emitDeveloperWarning: { _ in
            // TODO: has tentacles into TCA, lets avoid that and use the default swift one
            // runtimeWarn($0)
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

public struct DataDecoder {
    public func decode<T: Decodable>(_ data: Data) throws -> T {
        try jsonDecoder.decode(T.self, from: data)
    }

    var jsonDecoder: JSONDecoder
    static let production = Self(jsonDecoder: KlaviyoEnvironment.decoder)
}

public struct AnalyticsEnvironment {
    var networkSession: () -> NetworkSession
    var apiURL: String
    public var encodeJSON: (AnyEncodable) throws -> Data
    public var decoder: DataDecoder
    public var uuid: () -> UUID
    public var date: () -> Date
    public var timeZone: () -> String
    var appContextInfo: () -> AppContextInfo
    public var klaviyoAPI: KlaviyoAPI
    public var timer: (Double) -> AnyPublisher<Date, Never>

    // TODO: lets try and decouple state and action from core and try and add some mapping where ever appropriate
//    var send: (KlaviyoAction) -> Task<Void, Never>?
//    var state: () -> KlaviyoState
//    var statePublisher: () -> AnyPublisher<KlaviyoState, Never>
    static let production: AnalyticsEnvironment = {
        // TODO: lets try and decouple store from here
//        let store = Store.production
        AnalyticsEnvironment(
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
            }
//            send: { action in
//                store.send(action)
//            },
//            state: { store.state.value },
//            statePublisher: { store.state.eraseToAnyPublisher() }
        )
    }()
}
