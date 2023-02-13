//
//  KlaviyoAPI.swift
//  
//
//  Created by Noah Durell on 11/8/22.
//

import Foundation
import AnyCodable


@_spi(KlaviyoPrivate)
public struct KlaviyoAPI {
    @_spi(KlaviyoPrivate)
    public struct KlaviyoRequest: Equatable, Codable {
        public let apiKey: String
        public let endpoint: KlaviyoEndpoint
        public var uuid = environment.analytics.uuid().uuidString
    }
    
    @_spi(KlaviyoPrivate)
    public enum KlaviyoAPIError: Error {
        case httpError(Int, Data)
        case rateLimitError
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case internalRequestError(Error)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }
    
    // For internal testing use only
    @_spi(KlaviyoPrivate)  public static var requestStarted: (KlaviyoRequest, URLRequest) -> Void = { _, _ in }
    @_spi(KlaviyoPrivate)  public static var requestCompleted: (KlaviyoRequest, Data, HTTPURLResponse) -> Void = { _, _, _ in }
    @_spi(KlaviyoPrivate)  public static var requestFailed: (KlaviyoRequest, Error) -> Void = { _, _ in }
    @_spi(KlaviyoPrivate)  public static var requestRateLimited: (KlaviyoRequest) -> Void = { _ in }
    @_spi(KlaviyoPrivate)  public static var requestHttpError: (KlaviyoRequest, Int) -> Void = { _, _ in }
 
    var send:  (KlaviyoRequest) async -> Result<Data, KlaviyoAPIError> = { request in
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            requestFailed(request, error)
            return .failure(.internalRequestError(error))
        }
        
        requestStarted(request, urlRequest)
        var response: URLResponse
        var data: Data
        do {
            (data, response)  = try await environment.analytics.networkSession().data(urlRequest)
        } catch {
            requestFailed(request, error)
            return .failure(KlaviyoAPIError.networkError(error))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }
        if httpResponse.statusCode == 429 {
            requestRateLimited(request)
            return .failure(KlaviyoAPIError.rateLimitError)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            requestHttpError(request, httpResponse.statusCode)
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }
        requestCompleted(request, data, httpResponse)
        return .success(data)
        
    }
}

extension KlaviyoAPI.KlaviyoRequest {
    func urlRequest() throws -> URLRequest {
        guard let url = self.url else {
            throw KlaviyoAPI.KlaviyoAPIError.internalError("Invalid url string. API URL: \(environment.analytics.apiURL)")
        }
        var request = URLRequest(url: url)
        // We only support post right now
        guard let body = try? self.encodeBody() else {
            throw KlaviyoAPI.KlaviyoAPIError.dataEncodingError(self)
        }
        request.httpBody = body
        request.httpMethod = "POST"
        
        return request
        
    }
    
    var url: URL? {
        switch self.endpoint {
        case .createProfile, .createEvent:
            return URL(string: "\(environment.analytics.apiURL)/\(path)/?company_id=\(self.apiKey)")
        case .storePushToken:
            return URL(string: "\(environment.analytics.apiURL)/\(path)")
        }
    }
                            
    var path: String {
        switch self.endpoint {
        case .createProfile:
            return "client/profiles"
        case .createEvent:
            return "client/events"
        case .storePushToken:
            return "api/identify"
        }
    }
    
    func encodeBody() throws -> Data {
        switch self.endpoint {
        case .createProfile(let payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        case .createEvent(let payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        case .storePushToken(let payload):
            return try environment.analytics.encodeJSON(AnyEncodable(payload))
        }
    }
}

