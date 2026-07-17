//
// MenuItem.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation
import UIKit

struct MenuItem: Hashable, Codable {
    var name: String
    var id: Int
    var description: String
    var price = 10.99
    var numberOfItems = 0
}
