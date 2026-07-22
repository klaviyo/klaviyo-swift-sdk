//
//  KlaviyoSDKModule.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 7/14/26.
//

/// Marker protocol that anchors public `KlaviyoSDK` API extensions declared in feature modules
/// (Forms, Location) without those modules importing `KlaviyoSwift`.
///
/// `KlaviyoSwift` conforms `KlaviyoSDK` to this protocol. Feature modules extend
/// `KlaviyoSDKModule` instead of `KlaviyoSDK` directly, depending only on `KlaviyoCore` for the
/// type anchor. At a concrete call site the extension member resolves and `Self` binds to
/// `KlaviyoSDK`, so the public API and method chaining are preserved.
public protocol KlaviyoSDKModule {}
