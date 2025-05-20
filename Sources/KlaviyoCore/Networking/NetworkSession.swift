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
        "revision": NetworkSession.currentApiRevision,
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

    fileprivate static let currentApiRevision = "2024-10-15"
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

    public static let production = { () -> NetworkSession in
        let session = createEmphemeralSession()

        return NetworkSession(data: { request async throws -> (Data, URLResponse) in

            session.configuration.protocolClasses = URLProtocolOverrides.protocolClasses
            if #available(iOS 15, *) {
                return try await session.data(for: request)
            } else {
                return try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                    session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(with: Result.success((data!, response!)))
                        }
                    }.resume()
                }
            }
        })
    }()
}

public enum URLProtocolOverrides {
    public static var protocolClasses = [AnyClass]()
}
