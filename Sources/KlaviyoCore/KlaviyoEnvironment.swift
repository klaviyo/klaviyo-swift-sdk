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
#if canImport(os)
import os
#endif

public var environment = KlaviyoEnvironment.production

public struct KlaviyoEnvironment {
    public static let productionHost = "https://a.klaviyo.com"
    public static let encoder = { () -> JSONEncoder in
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder = { () -> JSONDecoder in
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let reachabilityService = Reachability(hostname: URL(string: productionHost)!.host!)

    public var archiverClient: ArchiverClient
    public var fileClient: FileClient
    public var data: (URL) throws -> Data
    public var logger: LoggerClient
//    public var analytics: AnalyticsEnvironment
    public var getUserDefaultString: (String) -> String?
    public var appLifeCycle: AppLifeCycleEvents
    public var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    public var getNotificationSettings: (@escaping (PushEnablement) -> Void) -> Void
    public var getBackgroundSetting: () -> PushBackground
    public var legacyIdentifier: () -> String
    public var startReachability: () throws -> Void
    public var stopReachability: () -> Void
    public var reachabilityStatus: () -> Reachability.NetworkStatus?
    public var randomInt: () -> Int
    // TODO: need to fix this
//    public var stateChangePublisher: () -> AnyPublisher<KlaviyoAction, Never>
    public var raiseFatalError: (String) -> Void
    public var emitDeveloperWarning: (String) -> Void
    static var production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        data: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        // TODO: fixme
        // analytics: AnalyticsEnvironment.production,
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
        // TODO: need to fix this
//        stateChangePublisher: StateChangePublisher().publisher,
        raiseFatalError: { msg in
            #if DEBUG
            fatalError(msg)
            #endif
        },
        emitDeveloperWarning: { runtimeWarn($0) })
}

public var networkSession: NetworkSession!
public func createNetworkSession() -> NetworkSession {
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

    public var jsonDecoder: JSONDecoder
    public static let production = Self(jsonDecoder: KlaviyoEnvironment.decoder)
}

public enum PushEnablement: String, Codable {
    case notDetermined = "NOT_DETERMINED"
    case denied = "DENIED"
    case authorized = "AUTHORIZED"
    case provisional = "PROVISIONAL"
    case ephemeral = "EPHEMERAL"

    static func create(from status: UNAuthorizationStatus) -> PushEnablement {
        switch status {
        case .denied:
            return PushEnablement.denied
        case .authorized:
            return PushEnablement.authorized
        case .provisional:
            return PushEnablement.provisional
        case .ephemeral:
            return PushEnablement.ephemeral
        default:
            return PushEnablement.notDetermined
        }
    }
}

public enum PushBackground: String, Codable {
    case available = "AVAILABLE"
    case restricted = "RESTRICTED"
    case denied = "DENIED"

    static func create(from status: UIBackgroundRefreshStatus) -> PushBackground {
        switch status {
        case .available:
            return PushBackground.available
        case .restricted:
            return PushBackground.restricted
        case .denied:
            return PushBackground.denied
        @unknown default:
            return PushBackground.available
        }
    }
}

@usableFromInline
@inline(__always)
func runtimeWarn(
    _ message: @autoclosure () -> String,
    category: String? = __klaviyoSwiftName,
    file: StaticString? = nil,
    line: UInt? = nil) {
    #if DEBUG
    let message = message()
    let category = category ?? "Runtime Warning"
    #if canImport(os)
    os_log(
        .fault,
        log: OSLog(subsystem: "com.apple.runtime-issues", category: category),
        "%@",
        message)
    #endif
    #endif
}

public var analytics = AnalyticsEnvironment.production

public struct AnalyticsEnvironment {
    var networkSession: () -> NetworkSession
    var apiURL: String
    var encodeJSON: (AnyEncodable) throws -> Data
    var decoder: DataDecoder
    public var uuid: () -> UUID
    var date: () -> Date
    var timeZone: () -> String
    var appContextInfo: () -> AppContextInfo
    var klaviyoAPI: KlaviyoAPI
    var timer: (Double) -> AnyPublisher<Date, Never>
    static let production: AnalyticsEnvironment = .init(
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
        })
}
