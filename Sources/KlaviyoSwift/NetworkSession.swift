//
//  NetworkSession.swift
//  Wrapper class for URLSession.
//
//  Created by Noah Durell on 11/3/22.
//

import Foundation

let CURRENT_API_REVISION = "2022-10-17"
let APPLICATION_JSON = "application/json"
let ACCEPTED_ENCODINGS = ["br", "gzip", "deflate"]

let defaultUserAgent = { () -> String in
    let appContext = environment.analytics.appContextInfo()
    let klaivyoSDKVersion = "klaviyo-ios/\(__klaviyoSwiftVersion)"
    return "\(appContext.excutable)/\(appContext.appVersion) (\(appContext.bundleId); build:\(appContext.appBuild); \(appContext.osVersionName)) \(klaivyoSDKVersion)"
}()

func createEmphemeralSession(protocolClasses: [AnyClass] = URLProtocolOverrides.protocolClasses) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpAdditionalHeaders = [
        "Accept-Encoding": ACCEPTED_ENCODINGS,
        "User-Agent": defaultUserAgent,
        "revision": CURRENT_API_REVISION,
        "content-type": APPLICATION_JSON,
        "accept": APPLICATION_JSON
    ]
    configuration.protocolClasses = protocolClasses
    return URLSession(configuration: configuration)
}

struct NetworkSession {
    var data: (URLRequest) async throws -> (Data, URLResponse)

    static let production = { () -> NetworkSession in
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
