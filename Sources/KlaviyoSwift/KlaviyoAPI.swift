//
//  KlaviyoAPI.swift
//  
//
//  Created by Noah Durell on 11/8/22.
//

import Foundation


struct KlaviyoAPI {
    struct KlaviyoRequest: Equatable, Codable {
        let apiKey: String
        let endpoint: KlaviyoEndpoint
        var uuid = environment.analytics.uuid().uuidString
    }
    
    enum KlaviyoAPIError: Error {
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
    
    var send:  (KlaviyoRequest) async -> Result<Data, KlaviyoAPIError> = { request in
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            return .failure(.internalRequestError(error))
        }
        
        var response: URLResponse
        var data: Data
        do {
            (data, response)  = try await environment.analytics.networkSession().data(urlRequest)
        } catch {
            return .failure(KlaviyoAPIError.networkError(error))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.missingOrInvalidResponse(response))
        }
        if httpResponse.statusCode == 429 {
            return .failure(KlaviyoAPIError.rateLimitError)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            return .failure(KlaviyoAPIError.httpError(httpResponse.statusCode, data))
        }
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
            return try environment.analytics.encodeJSON(payload)
        case .createEvent(let payload):
            return try environment.analytics.encodeJSON(payload)
        case .storePushToken(let payload):
            return try environment.analytics.encodeJSON(payload)
        }
    }
}

