//
//  KlaviyoEnvironment.swift
//  KlaviyoSwift
//
//  Created by Noah Durell on 9/28/22.
//

import Combine
import Foundation
import KlaviyoSDKDependencies
import UIKit

// Though this is a var it should never be modified outside of tests.
#if swift(>=5.10)
public internal(set) nonisolated(unsafe) var environment = KlaviyoEnvironment.production
#else
public internal(set) var environment = KlaviyoEnvironment.production
#endif

public struct KlaviyoEnvironment: Sendable {
    public init(
        archiverClient: ArchiverClient,
        fileClient: FileClient,
        dataFromUrl: @Sendable @escaping (URL) throws -> Data,
        logger: LoggerClient,
        notificationCenterPublisher: @Sendable @escaping (NSNotification.Name) -> AnyPublisher<Notification, Never>,
        getNotificationSettings: @Sendable @escaping () async -> PushEnablement,
        getBadgeAutoClearingSetting: @Sendable @escaping () async -> Bool,
        startReachability: @Sendable @escaping () throws -> Void,
        stopReachability: @Sendable @escaping () -> Void,
        reachabilityStatus: @Sendable @escaping () -> Reachability
            .NetworkStatus?,
        randomInt: @Sendable @escaping () -> Int,
        raiseFatalError: @Sendable @escaping (String) -> Void,
        emitDeveloperWarning: @Sendable @escaping (String) -> Void,
        apiURL: @Sendable @escaping () -> URLComponents,
        cdnURL: @Sendable @escaping () -> URLComponents,
        encodeJSON: @Sendable @escaping (Encodable) throws -> Data,
        decoder: DataDecoder,
        uuid: @Sendable @escaping () -> UUID,
        date: @Sendable @escaping () -> Date,
        timeZone: @Sendable @escaping () -> String,
        klaviyoAPI: KlaviyoAPI,
        timer: @Sendable @escaping (Double) -> AsyncStream<Date>,
        appContextInfo: @Sendable @escaping () async -> AppContextInfo
    ) {
        self.archiverClient = archiverClient
        self.fileClient = fileClient
        self.dataFromUrl = dataFromUrl
        self.logger = logger
        self.notificationCenterPublisher = notificationCenterPublisher
        self.getNotificationSettings = getNotificationSettings
        self.getBadgeAutoClearingSetting = getBadgeAutoClearingSetting
        self.startReachability = startReachability
        self.stopReachability = stopReachability
        self.reachabilityStatus = reachabilityStatus
        self.randomInt = randomInt
        self.raiseFatalError = raiseFatalError
        self.emitDeveloperWarning = emitDeveloperWarning
        self.apiURL = apiURL
        self.cdnURL = cdnURL
        self.encodeJSON = encodeJSON
        self.decoder = decoder
        self.uuid = uuid
        self.date = date
        self.timeZone = timeZone
        self.klaviyoAPI = klaviyoAPI
        self.timer = timer
        self.appContextInfo = appContextInfo
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
    public var dataFromUrl: @Sendable (URL) throws -> Data

    public var logger: LoggerClient

    public var notificationCenterPublisher:
        @Sendable (NSNotification.Name) -> AnyPublisher<Notification, Never>
    public var getNotificationSettings: @Sendable () async -> PushEnablement
    public var getBadgeAutoClearingSetting: @Sendable () async -> Bool
    public var startReachability: @Sendable () throws -> Void
    public var stopReachability: @Sendable () -> Void
    public var reachabilityStatus: @Sendable () -> Reachability.NetworkStatus?
    public var randomInt: @Sendable () -> Int
    public var raiseFatalError: @Sendable (String) -> Void
    public var emitDeveloperWarning: @Sendable (String) async -> Void
    public var apiURL: @Sendable () -> URLComponents
    public var cdnURL: @Sendable () -> URLComponents
    public var encodeJSON: @Sendable (Encodable) throws -> Data
    public var decoder: DataDecoder
    public var uuid: @Sendable () -> UUID
    public var date: @Sendable () -> Date
    public var timeZone: @Sendable () -> String
    public var klaviyoAPI: KlaviyoAPI
    public var timer: @Sendable (Double) -> AsyncStream<Date>
    public var appContextInfo: @Sendable () async -> AppContextInfo

    public static let production = KlaviyoEnvironment(
        archiverClient: ArchiverClient.production,
        fileClient: FileClient.production,
        dataFromUrl: { url in try Data(contentsOf: url) },
        logger: LoggerClient.production,
        notificationCenterPublisher: { name in
            NotificationCenter.default.publisher(for: name)
                .eraseToAnyPublisher()
        },
        getNotificationSettings: {
            let notificationSettings = await UNUserNotificationCenter.current()
                .notificationSettings()
            return PushEnablement.create(
                from: notificationSettings.authorizationStatus)
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
        apiURL: { KlaviyoEnvironment.productionHost },
        cdnURL: { KlaviyoEnvironment.cdnHost },
        encodeJSON: { encodable in try encoder.encode(encodable) },
        decoder: DataDecoder.production,
        uuid: { UUID() },
        date: { Date() },
        timeZone: { TimeZone.autoupdatingCurrent.identifier },
        klaviyoAPI: KlaviyoAPI(),
        timer: { interval in
            AsyncStream { continuation in
                let timerActor = TimerActor()
                Task {
                    // Start the timer via the TimerActor
                    #if swift(>=6)
                    timerActor.startTimer(interval: interval, continuation: continuation)
                    #else
                    await timerActor.startTimer(interval: interval, continuation: continuation)
                    #endif
                }

                continuation.onTermination = { _ in
                    // Stop the timer when the stream terminates
                    Task {
                        #if swift(>=6)
                        timerActor.stopTimer()
                        #else
                        await timerActor.stopTimer()
                        #endif
                    }
                }
            }
        }, appContextInfo: {
            #if swift(>=6)
            getDefaultAppContextInfo()
            #else
            await getDefaultAppContextInfo()
            #endif
        })
}

@MainActor var networkSession: NetworkSession? = nil

@MainActor
public func createNetworkSession() -> NetworkSession {
    if networkSession == nil {
        networkSession = NetworkSession.production
    }
    return networkSession!
}

public enum KlaviyoDecodingError: Error {
    case invalidType
}

public struct DataDecoder: @unchecked Sendable {
    public init(jsonDecoder: JSONDecoder) {
        self.jsonDecoder = jsonDecoder
    }

    public var jsonDecoder: JSONDecoder
    public static let production = Self(jsonDecoder: KlaviyoEnvironment.decoder)

    public func decode<T: Decodable>(_ data: Data) throws -> T {
        try jsonDecoder.decode(T.self, from: data)
    }
}

actor TimerActor {
    private var timer: DispatchSourceTimer?

    func startTimer(
        interval: TimeInterval, continuation: AsyncStream<Date>.Continuation) {
        // Ensure any previous timer is invalidated
        stopTimer()

        // Create a new DispatchSourceTimer and start it
        let newTimer = DispatchSource.makeTimerSource(queue: .global())
        newTimer.schedule(deadline: .now(), repeating: interval)
        newTimer.setEventHandler {
            continuation.yield(Date())
        }
        newTimer.resume()
        timer = newTimer
    }

    func stopTimer() {
        // Invalidate the existing timer if there is one
        timer?.cancel()
        timer = nil
    }
}
