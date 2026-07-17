//
// User.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

struct User {
    var firstName: String?
    var lastName: String?
    var zipcode: String!
    var email: String?
    var cart: [MenuItem]?
    var isLoggedIn: Bool?
}
