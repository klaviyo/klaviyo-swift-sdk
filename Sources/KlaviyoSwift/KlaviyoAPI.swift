//
//  KlaviyoAPI.swift
//  
//
//  Created by Noah Durell on 11/8/22.
//

import Foundation


struct KlaviyoAPI {
    struct KlaviyoRequest: Encodable {
      let apiKey: String
      let endpoint: KlaviyoEndpoint
        
        enum CodingKeys: CodingKey {
            case apiKey
            case endpoint
        }
    }
    
    enum KlaviyoAPIError: Error {
        case httpError(Int, Data?)
        case rateLimitError
        case missingOrInvalidResponse(URLResponse?)
        case networkError(Error)
        case internalError(String)
        case internalRequestError(Error)
        case unknownError(Error)
        case dataEncodingError(KlaviyoRequest)
        case invalidData
    }
    
    var sendRequest: (KlaviyoRequest, @escaping (Result<Data, KlaviyoAPIError>) -> Void) -> Void = { request, result in
        var urlRequest: URLRequest
        do {
            urlRequest = try request.urlRequest()
        } catch {
            result(.failure(.internalRequestError(error)))
            return
        }
        environment.analytics.networkSession().dataTask(urlRequest) { data, response, error in
            if let networkError = error {
                result(.failure(KlaviyoAPIError.networkError(networkError)))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                result(.failure(KlaviyoAPIError.missingOrInvalidResponse(response)))
                return
            }
            guard 200 ..< 300 ~= response.statusCode else {
                result(.failure(KlaviyoAPIError.httpError(response.statusCode, data)))
                return
            }
            guard let data = data else {
                result(.failure(.invalidData))
                return
            }
            result(.success(data))
        }
    }
}
