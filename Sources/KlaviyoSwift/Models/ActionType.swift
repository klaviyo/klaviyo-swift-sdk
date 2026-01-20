//
//  ActionType.swift
//
//  Klaviyo Swift SDK
//
//  Created for Klaviyo
//
//  Copyright (c) 2025 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents the supported action types for push notification buttons.
public enum ActionType: String, Equatable {
    case openApp = "open_app"
    case deepLink = "deep_link"
}
