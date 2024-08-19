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
    public init(
        archiverClient: ArchiverClient,
        fileClient: FileClient,
        dataFromUrl: @escaping (URL) throws -> Data,
        logger: LoggerClient,
        appLifeCycle: AppLifeCycleEvents,
        notificationCenterPublisher: @escaping (NSNotification.Name) -> AnyPublisher<Notification, Never>,
        getNotificationSettings: @escaping (@escaping (PushEnablement) -> Void) -> Void,
        getBackgroundSetting: @escaping () -> PushBackground,
        startReachability: @escaping () throws -> Void,
        stopReachability: @escaping () -> Void,
        reachabilityStatus: @escaping () -> Reachability.NetworkStatus?,
        randomInt: @escaping () -> Int,
        raiseFatalError: @escaping (String) -> Void,
        emitDeveloperWarning: @escaping (String) -> Void,
        networkSession: @escaping () -> NetworkSession,
        apiURL: String,
        encodeJSON: @escaping (AnyEncodable) throws -> Data,
        decoder: DataDecoder,
        uuid: @escaping () -> UUID,
        date: @escaping () -> Date,
        timeZone: @escaping () -> String,
        appContextInfo: @escaping () -> AppContextInfo,
        klaviyoAPI: KlaviyoAPI,
        timer: @escaping (Double) -> AnyPublisher<Date, Never>) {
        self.archiverClient = archiverClient
        self.fileClient = fileClient
        self.dataFromUrl = dataFromUrl
        self.logger = logger
        self.appLifeCycle = appLifeCycle
        self.notificationCenterPublisher = notificationCenterPublisher
        self.getNotificationSettings = getNotificationSettings
        self.getBackgroundSetting = getBackgroundSetting
        self.startReachability = startReachability
        self.stopReachability = stopReachability
        self.reachabilityStatus = reachabilityStatus
        self.randomInt = randomInt
        self.raiseFatalError = raiseFatalError
        self.emitDeveloperWarning = emitDeveloperWarning
        self.networkSession = networkSession
        self.apiURL = apiURL
        self.encodeJSON = encodeJSON
        self.decoder = decoder
        self.uuid = uuid
        self.date = date
        self.timeZone = timeZone
        self.appContextInfo = appContextInfo
        self.klaviyoAPI = klaviyoAPI
        self.timer = timer
    }

    static let productionHost = "https://a.klaviyo.com"
    public static let encoder = { () -> JSONEncoder in
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

    public var archiverClient: ArchiverClient
    public var fileClient: FileClient
    public var dataFromUrl: (URL) throws -> Data

    public var logger: LoggerClient

    public var appLifeCycle: AppLifeCycleEvents

    public var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    public var getNotificationSettings: (@escaping (PushEnablement) -> Void) -> Void
    public var getBackgroundSetting: () -> PushBackground

    public var startReachability: () throws -> Void
    public var stopReachability: () -> Void
    public var reachabilityStatus: () -> Reachability.NetworkStatus?

    public var randomInt: () -> Int

    public var raiseFatalError: (String) -> Void
    public var emitDeveloperWarning: (String) -> Void

    public var networkSession: () -> NetworkSession
    public var apiURL: String
    public var encodeJSON: (AnyEncodable) throws -> Data
    public var decoder: DataDecoder
    public var uuid: () -> UUID
    public var date: () -> Date
    public var timeZone: () -> String
    public var appContextInfo: () -> AppContextInfo
    public var klaviyoAPI: KlaviyoAPI
    public var timer: (Double) -> AnyPublisher<Date, Never>

    public static var production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        dataFromUrl: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
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
        raiseFatalError: { msg in
            #if DEBUG
            fatalError(msg)
            #endif
        },
        emitDeveloperWarning: { runtimeWarn($0) },
        networkSession: createNetworkSession,
        apiURL: KlaviyoEnvironment.productionHost,
        encodeJSON: { encodable in try encoder.encode(encodable) },
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

public var networkSession: NetworkSession!
public func createNetworkSession() -> NetworkSession {
    if networkSession == nil {
        networkSession = NetworkSession.production
    }
    return networkSession
}

public enum KlaviyoDecodingError: Error {
    case invalidType
}

public struct DataDecoder {
    public init(jsonDecoder: JSONDecoder) {
        self.jsonDecoder = jsonDecoder
    }

    public var jsonDecoder: JSONDecoder
    public static let production = Self(jsonDecoder: KlaviyoEnvironment.decoder)

    public func decode<T: Decodable>(_ data: Data) throws -> T {
        try jsonDecoder.decode(T.self, from: data)
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
