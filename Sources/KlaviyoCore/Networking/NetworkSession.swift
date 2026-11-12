//
//  NetworkSession.swift
//  Wrapper class for URLSession.
//
//  Created by Noah Durell on 11/3/22.
//

import Foundation

public func createEmphemeralSession(protocolClasses: [AnyClass] = URLProtocolOverrides.protocolClasses) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpAdditionalHeaders = [
        "Accept-Encoding": NetworkSession.acceptedEncodings,
        "User-Agent": NetworkSession.defaultUserAgent,
        "content-type": NetworkSession.applicationJson,
        "accept": NetworkSession.applicationJson,
        "X-Klaviyo-Mobile": NetworkSession.mobileHeader
    ]
    configuration.protocolClasses = protocolClasses
    return URLSession(configuration: configuration)
}

public struct NetworkSession {
    public var data: (URLRequest) async throws -> (Data, URLResponse)

    public init(data: @escaping (URLRequest) async throws -> (Data, URLResponse)) {
        self.data = data
    }

    fileprivate static let applicationJson = "application/json"
    fileprivate static let acceptedEncodings = ["br", "gzip", "deflate"]
    fileprivate static let mobileHeader = "1"

    public static let networkTimeout: UInt64 = 10_000_000_000 // in nanoseconds (10 seconds)

    private static func getPluginConfiguration(bundle: Bundle = .main) -> (name: String, version: String)? {
        guard let plistURL = bundle.url(forResource: "klaviyo-plugin-configuration", withExtension: "plist"),
              let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        guard let pluginName = plist["klaviyo_sdk_plugin_name_override"] as? String,
              let pluginVersion = plist["klaviyo_sdk_plugin_version_override"] as? String
        else {
            return nil
        }

        return (name: pluginName, version: pluginVersion)
    }

    public static var defaultUserAgent: String = defaultUserAgent(bundle: .main)

    internal static func defaultUserAgent(bundle: Bundle) -> String {
        let appContext = environment.appContextInfo()
        let klaivyoSDKVersion = "klaviyo-\(environment.sdkName())/\(environment.sdkVersion())"
        var userAgent = "\(appContext.executable)/\(appContext.appVersion) (\(appContext.bundleId); build:\(appContext.appBuild); \(appContext.osVersionName)) \(klaivyoSDKVersion)"
        // checks if we're using a react native framework (ex. Expo) to assemble, and appending to user agent
        if let pluginConfig = getPluginConfiguration(bundle: bundle) {
            userAgent += " (\(pluginConfig.name)/\(pluginConfig.version))"
        }

        return userAgent
    }

    /// iOS 13/14 path: `dataTask` ignores Swift cancellation, so cancel the task explicitly.
    /// A task cancelled before it starts never runs its handler, so resume that case ourselves.
    static func dataTaskFallback(session: URLSession, request: URLRequest) async throws -> (Data, URLResponse) {
        let box = DataTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.set(task)
                if Task.isCancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    private final class DataTaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false

        func set(_ task: URLSessionDataTask) {
            lock.lock()
            self.task = task
            let wasCancelled = cancelled
            lock.unlock()
            if wasCancelled { task.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }
    }

    public static let production = { () -> NetworkSession in
        let session = createEmphemeralSession()

        return NetworkSession(data: { request async throws -> (Data, URLResponse) in

            session.configuration.protocolClasses = URLProtocolOverrides.protocolClasses
            if #available(iOS 15, *) {
                return try await session.data(for: request)
            } else {
                return try await dataTaskFallback(session: session, request: request)
            }
        })
    }()
}

public enum URLProtocolOverrides {
    public static var protocolClasses = [AnyClass]()
}
