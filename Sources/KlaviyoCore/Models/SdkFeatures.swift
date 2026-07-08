//
//  SdkFeatures.swift
//  KlaviyoCore
//
//  Models the SDK feature flags reported via the `X-Klaviyo-Sdk-Features` header on the
//  push-token-register request, used for SDK adoption telemetry.
//

import Foundation

/// Snapshot of the SDK feature flags reported to the backend for adoption telemetry, serialized
/// into the `X-Klaviyo-Sdk-Features` header.
///
/// Each feature reports its own configured state independently, so the backend gets a faithful
/// signal of how the host set each flag. A feature is only reported when the host actually set its
/// Info.plist key; fields whose key is absent are omitted from the header (the feature is "not
/// marked as used") rather than reported with a default value.
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

    /// Master automatic-push-tracking flag, or `nil` when the key is absent from Info.plist
    /// (the field is then omitted from the header).
    public let autoPushTracking: Bool?
    /// Whether automatic token forwarding is enabled (i.e. the escape hatch is not set), independent
    /// of the master flag. `nil` when the escape-hatch key is absent from Info.plist, in which case the
    /// field is omitted from the header, so the backend must treat its absence as "unknown", not `false`.
    public let autoPushTokenForwarding: Bool?

    /// - Parameters:
    ///   - autoPushTracking: value of the master `klaviyo_automatic_push_tracking` flag, or `nil`
    ///     when that key is absent from Info.plist.
    ///   - autoTokenForwardingDisabled: value of the `klaviyo_disable_automatic_token_forwarding`
    ///     escape hatch, or `nil` when that key is absent from Info.plist.
    public init(autoPushTracking: Bool?, autoTokenForwardingDisabled: Bool?) {
        self.autoPushTracking = autoPushTracking
        // Report each flag's configured state independently. Token forwarding is considered enabled
        // unless the escape hatch explicitly disables it; this is decoupled from the master flag so we
        // capture how the host set each flag rather than a collapsed runtime state.
        autoPushTokenForwarding = autoTokenForwardingDisabled.map { !$0 }
    }

    /// Value for the `X-Klaviyo-Sdk-Features` header, e.g. `auto_push_tracking=1; auto_push_token_forwarding=0;`.
    /// Only features whose Info.plist key was set are included; unset features are omitted.
    public var headerValue: String {
        var fields: [String] = []
        if let autoPushTracking {
            fields.append("auto_push_tracking=\(autoPushTracking ? 1 : 0)")
        }
        if let autoPushTokenForwarding {
            fields.append("auto_push_token_forwarding=\(autoPushTokenForwarding ? 1 : 0)")
        }
        return fields.isEmpty ? "" : fields.joined(separator: "; ") + ";"
    }
}
