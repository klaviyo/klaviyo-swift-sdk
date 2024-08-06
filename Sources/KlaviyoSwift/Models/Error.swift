//
//  File.swift
//
//
//  Created by Ajay Subramanya on 8/6/24.
//

import Foundation

struct ErrorResponse: Codable {
    let errors: [ErrorDetail]
}

struct ErrorDetail: Codable {
    let id: String
    let status: Int
    let code: String
    let title: String
    let detail: String
    let source: ErrorSource
}

struct ErrorSource: Codable {
    let pointer: String
}
