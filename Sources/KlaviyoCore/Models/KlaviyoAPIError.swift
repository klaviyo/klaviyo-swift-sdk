//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/8/24.
//

import Foundation

public enum KlaviyoAPIError: Error {
    case httpError(Int, Data)
    case rateLimitError(Int)
    case missingOrInvalidResponse(URLResponse?)
    case networkError(Error)
    case internalError(String)
    case internalRequestError(Error)
    case unknownError(Error)
    case dataEncodingError(KlaviyoRequest)
    case invalidData
}
