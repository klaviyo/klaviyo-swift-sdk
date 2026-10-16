//
//  Event.swift
//  KlaviyoSwift
//

import KlaviyoCore

/// Re-exports ``KlaviyoCore/Event`` so host code that imports only `KlaviyoSwift`
/// can call ``KlaviyoSDK/create(event:)`` without a second import.
public typealias Event = KlaviyoCore.Event
