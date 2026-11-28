//
//  FeatureFlags.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 9/17/26.
//

import Foundation

/// Internal, injectable feature gates for behaviors that diverge from the Android SDK. All default
/// to false (Android parity). Not part of the public initialize() API — integrators cannot toggle
/// these.
public struct FeatureFlags: Equatable {
    /// Durably buffer ALL pre-init calls to disk and attribute at initialize(). OFF (parity): drop
    /// pre-init calls, holding only push-opens in a non-durable in-memory buffer.
    public var enablePreInitDiskCapture: Bool
    /// On a company (apiKey) switch, mint a fresh anon for an identified profile + clear PII + reset
    /// staged props, then re-register the token identity-only. OFF (parity): preserve the profile
    /// (keep PII + anon, no reset) and re-register the token carrying the existing full profile.
    public var enableCompanySwitchReset: Bool

    public init(
        enablePreInitDiskCapture: Bool = false,
        enableCompanySwitchReset: Bool = false
    ) {
        self.enablePreInitDiskCapture = enablePreInitDiskCapture
        self.enableCompanySwitchReset = enableCompanySwitchReset
    }

    public static let production = FeatureFlags()
}

/// Process-wide injection point, mirroring `environment`. Tests set this in setUp and restore
/// `.production` in tearDown.
public var featureFlags = FeatureFlags.production
