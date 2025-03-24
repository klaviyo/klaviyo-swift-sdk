//
//  NetworkSession.swift
//  Wrapper class for URLSession.
//
//  Created by Noah Durell on 11/3/22.
//

import Foundation

@MainActor var userAgent: String?

@MainActor public let defaultUserAgent = { () -> String in
    if let userAgent = userAgent {
        return userAgent
    }
    let appContext = environment.appContextInfo()
    let sdkVersion = appContext.sdkVersion
    let sdkName = appContext.klaviyoSdk
    let klaivyoSDKVersion = "klaviyo-\(sdkName)/\(sdkVersion)"
    let userAgent = "\(appContext.executable)/\(appContext.appVersion) (\(appContext.bundleId); build:\(appContext.appBuild); \(appContext.osVersionName)) \(klaivyoSDKVersion)"
    return userAgent
}

@MainActor var urlSession: URLSession?

@MainActor
public func createEmphemeralSession(userAgent: String, protocolClasses: [AnyClass] = URLProtocolOverrides.protocolClasses) -> URLSession {
    if let urlSession = urlSession {
        return urlSession
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpAdditionalHeaders = [
        "Accept-Encoding": NetworkSession.acceptedEncodings,
        "User-Agent": userAgent,
        "revision": NetworkSession.currentApiRevision,
        "content-type": NetworkSession.applicationJson,
        "accept": NetworkSession.applicationJson,
        "X-Klaviyo-Mobile": NetworkSession.mobileHeader
    ]
    configuration.protocolClasses = protocolClasses
    let session = URLSession(configuration: configuration)
    urlSession = session
    return session
}

public struct NetworkSession: Sendable {
    public var data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(data: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse)) {
        self.data = data
    }

    fileprivate static let currentApiRevision = "2024-10-15"
    fileprivate static let applicationJson = "application/json"
    fileprivate static let acceptedEncodings = ["br", "gzip", "deflate"]
    fileprivate static let mobileHeader = "1"

    public static let networkTimeout: UInt64 = 10_000_000_000 // in nanoseconds (10 seconds)

    public static let production = { () -> NetworkSession in

        NetworkSession(data: { request async throws -> (Data, URLResponse) in
            let userAgent = defaultUserAgent()
            #if swift(>=6)
            let session = createEmphemeralSession(userAgent: userAgent)
            #else
            let session = await createEmphemeralSession(userAgent: userAgent)
            #endif
            // ND: why assign protocols again??
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
    #if swift(>=6)
    public nonisolated(unsafe) static var protocolClasses = [AnyClass]()
    #else
    public static var protocolClasses = [AnyClass]()
    #endif
}
