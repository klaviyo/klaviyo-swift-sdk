//
//  SdkFeatures.swift
//  KlaviyoCore
//
//  Models the SDK feature flags reported via the `X-Klaviyo-Sdk-Features` header on the
//  push-token-register request, used for SDK adoption telemetry.
//

import Foundation

/// Snapshot of the automatic-push-tracking feature flags reported to the backend for
/// adoption telemetry. Serialized into the `X-Klaviyo-Sdk-Features` header.
///
/// A feature is only reported when the host app actually set its Info.plist key. Fields whose
/// key is absent are omitted from the header entirely (the feature is "not marked as used")
/// rather than reported with a default value.
public struct SdkFeatures: Equatable {
    /// Name of the HTTP header these features are serialized into on push-token registration.
    public static let headerName = "X-Klaviyo-Sdk-Features"

    /// Info.plist keys the host app sets to opt in to automatic push tracking behavior.
    /// Shared so the flag reads stay consistent across modules.
    package enum InfoPlistKey {
        /// Master flag: when present and `true`, enables proxy delegate injection and token forwarding.
        package static let automaticPushTracking = "klaviyo_automatic_push_tracking"
        /// Escape hatch: when `true` (and the master is `true`), token forwarding is skipped while the
        /// proxy stays active.
        package static let disableAutomaticTokenForwarding = "klaviyo_disable_automatic_token_forwarding"
    }

    /// Whether the master automatic-push-tracking flag is enabled. Always reported (the header is
    /// only built when the master key is present).
    public let autoPushTracking: Bool
    /// Effective token-forwarding state, or `nil` when the escape-hatch key is absent from Info.plist.
    /// When `nil` the field is omitted from the header rather than reported, so the backend must treat
    /// its absence as "unknown / not reported" — never as `false`.
    public let autoPushTokenForwarding: Bool?

    /// - Parameters:
    ///   - autoPushTrackingEnabled: value of the master `klaviyo_automatic_push_tracking` flag.
    ///   - autoTokenForwardingDisabled: value of the `klaviyo_disable_automatic_token_forwarding`
    ///     escape hatch, or `nil` when that key is absent from Info.plist (forwarding is then unreported).
    public init(autoPushTrackingEnabled: Bool, autoTokenForwardingDisabled: Bool?) {
        autoPushTracking = autoPushTrackingEnabled
        if let autoTokenForwardingDisabled {
            // Token forwarding is only active when tracking is on and the escape hatch is not set.
            autoPushTokenForwarding = autoPushTrackingEnabled && !autoTokenForwardingDisabled
        } else {
            autoPushTokenForwarding = nil
        }
    }

    /// Value for the `X-Klaviyo-Sdk-Features` header, e.g. `auto_push_tracking=1; auto_push_token_forwarding=0;`.
    /// Only features whose Info.plist key was set are included; unset features are omitted.
    public var headerValue: String {
        var fields = ["auto_push_tracking=\(autoPushTracking ? 1 : 0)"]
        if let autoPushTokenForwarding {
            fields.append("auto_push_token_forwarding=\(autoPushTokenForwarding ? 1 : 0)")
        }
        return fields.joined(separator: "; ") + ";"
    }
}
