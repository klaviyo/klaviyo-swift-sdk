//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Combine
import Foundation
import UIKit

public var environment = KlaviyoEnvironment.production

public struct KlaviyoEnvironment {
    public init(
        archiverClient: ArchiverClient,
        fileClient: FileClient,
        dataFromUrl: @escaping (URL) throws -> Data,
        logger: LoggerClient,
        appLifeCycle: AppLifeCycleEvents,
        notificationCenterPublisher: @escaping (NSNotification.Name) -> AnyPublisher<Notification, Never>,
        getNotificationSettings: @escaping () async -> PushEnablement,
        getBackgroundSetting: @escaping () -> PushBackground,
        getBadgeAutoClearingSetting: @escaping () async -> Bool,
        startReachability: @escaping () throws -> Void,
        stopReachability: @escaping () -> Void,
        reachabilityStatus: @escaping () -> Reachability.NetworkStatus?,
        randomInt: @escaping () -> Int,
        raiseFatalError: @escaping (String) -> Void,
        emitDeveloperWarning: @escaping (String) -> Void,
        networkSession: @escaping () -> NetworkSession,
        apiURL: @escaping () -> URLComponents,
        cdnURL: @escaping () -> URLComponents,
        encodeJSON: @escaping (Encodable) throws -> Data,
        decoder: DataDecoder,
        uuid: @escaping () -> UUID,
        date: @escaping () -> Date,
        timeZone: @escaping () -> String,
        appContextInfo: @escaping () -> AppContextInfo,
        klaviyoAPI: KlaviyoAPI,
        timer: @escaping (Double) -> AnyPublisher<Date, Never>,
        SDKName: @escaping () -> String,
        SDKVersion: @escaping () -> String
    ) {
        self.archiverClient = archiverClient
        self.fileClient = fileClient
        self.dataFromUrl = dataFromUrl
        self.logger = logger
        self.appLifeCycle = appLifeCycle
        self.notificationCenterPublisher = notificationCenterPublisher
        self.getNotificationSettings = getNotificationSettings
        self.getBackgroundSetting = getBackgroundSetting
        self.getBadgeAutoClearingSetting = getBadgeAutoClearingSetting
        self.startReachability = startReachability
        self.stopReachability = stopReachability
        self.reachabilityStatus = reachabilityStatus
        self.randomInt = randomInt
        self.raiseFatalError = raiseFatalError
        self.emitDeveloperWarning = emitDeveloperWarning
        self.networkSession = networkSession
        self.apiURL = apiURL
        self.cdnURL = cdnURL
        self.encodeJSON = encodeJSON
        self.decoder = decoder
        self.uuid = uuid
        self.date = date
        self.timeZone = timeZone
        self.appContextInfo = appContextInfo
        self.klaviyoAPI = klaviyoAPI
        self.timer = timer
        sdkName = SDKName
        sdkVersion = SDKVersion
    }

    static let productionHost: URLComponents = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "a.klaviyo.com"
        return components
    }()

    static let cdnHost: URLComponents = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "static.klaviyo.com"
        return components
    }()

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

    private static let reachabilityService = Reachability(hostname: productionHost.host ?? "")

    public var archiverClient: ArchiverClient
    public var fileClient: FileClient
    public var dataFromUrl: (URL) throws -> Data

    public var logger: LoggerClient

    public var appLifeCycle: AppLifeCycleEvents

    public var notificationCenterPublisher: (NSNotification.Name) -> AnyPublisher<Notification, Never>
    public var getNotificationSettings: () async -> PushEnablement
    public var getBackgroundSetting: () -> PushBackground
    public var getBadgeAutoClearingSetting: () async -> Bool

    public var startReachability: () throws -> Void
    public var stopReachability: () -> Void
    public var reachabilityStatus: () -> Reachability.NetworkStatus?

    public var randomInt: () -> Int

    public var raiseFatalError: (String) -> Void
    public var emitDeveloperWarning: (String) -> Void

    public var networkSession: () -> NetworkSession
    public var apiURL: () -> URLComponents
    public var cdnURL: () -> URLComponents
    public var encodeJSON: (Encodable) throws -> Data
    public var decoder: DataDecoder
    public var uuid: () -> UUID
    public var date: () -> Date
    public var timeZone: () -> String
    public var appContextInfo: () -> AppContextInfo
    public var klaviyoAPI: KlaviyoAPI
    public var timer: (Double) -> AnyPublisher<Date, Never>

    public var sdkName: () -> String
    public var sdkVersion: () -> String

    private static let rnSDKConfig: [String: AnyObject] = loadPlist(named: "klaviyo-sdk-configuration") ?? [:]

    private static func getSDKName() -> String {
        if let sdkName = KlaviyoEnvironment.rnSDKConfig["klaviyo_sdk_name"] as? String {
            return sdkName
        }
        return __klaviyoSwiftName
    }

    private static func getSDKVersion() -> String {
        if let sdkVersion = KlaviyoEnvironment.rnSDKConfig["klaviyo_sdk_version"] as? String {
            return sdkVersion
        }
        return __klaviyoSwiftVersion
    }

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
        getNotificationSettings: {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            return PushEnablement.create(from: notificationSettings.authorizationStatus)
        },
        getBackgroundSetting: {
            .create(from: UIApplication.shared.backgroundRefreshStatus)
        },
        getBadgeAutoClearingSetting: {
            Bundle.main.object(forInfoDictionaryKey: "klaviyo_badge_autoclearing") as? Bool ?? true
        },
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
        apiURL: { KlaviyoEnvironment.productionHost },
        cdnURL: { KlaviyoEnvironment.cdnHost },
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
        },
        SDKName: KlaviyoEnvironment.getSDKName,
        SDKVersion: KlaviyoEnvironment.getSDKVersion
    )
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
