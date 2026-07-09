//
//  SdkFeatures.swift
//  KlaviyoCore
//
//  Models the SDK feature flags reported via the `X-Klaviyo-Sdk-Features` header,
//  used for SDK adoption telemetry.
//

import Foundation

/// The request surface a feature is reported on. Each endpoint that carries the
/// `X-Klaviyo-Sdk-Features` header reports only the features belonging to its scope.
///
/// Kept separate from `KlaviyoEndpoint` cases so multiple endpoints can share a scope.
public enum SdkFeatureScope: Equatable, CaseIterable {
    /// Reported on the push-token-register request.
    case pushTokenRegistration
}

/// Catalog of reportable SDK features: each case pairs a feature's wire name (the raw value,
/// serialized into the header) with the scope it is reported on.
///
/// Adding a feature means adding a case here and assigning its scope; a feature is never
/// serialized onto requests outside its scope.
public enum SdkFeatureKey: String, CaseIterable {
    case autoPushTracking = "auto_push_tracking"
    case autoPushTokenForwarding = "auto_push_token_forwarding"

    /// The request surface this feature is reported on.
    var scope: SdkFeatureScope {
        switch self {
        case .autoPushTracking, .autoPushTokenForwarding:
            return .pushTokenRegistration
        }
    }
}

/// Snapshot of the SDK feature flags reported to the backend for adoption telemetry, serialized
/// into the `X-Klaviyo-Sdk-Features` header.
///
/// Each feature reports its own configured state independently, so the backend gets a faithful
/// signal of how the host set each flag. A feature is only present in the snapshot when the host
/// actually set its Info.plist key; features whose key is absent are omitted from the header
/// (the feature is "not marked as used") rather than reported with a default value.
public struct SdkFeatures: Equatable {
    /// Name of the HTTP header these features are serialized into.
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

    /// Configured feature states; only features the host actually configured are present.
    private let values: [SdkFeatureKey: Bool]

    public init(values: [SdkFeatureKey: Bool]) {
        self.values = values
    }

    /// - Parameters:
    ///   - autoPushTracking: value of the master `klaviyo_automatic_push_tracking` flag, or `nil`
    ///     when that key is absent from Info.plist.
    ///   - autoTokenForwardingDisabled: value of the `klaviyo_disable_automatic_token_forwarding`
    ///     escape hatch, or `nil` when that key is absent from Info.plist.
    public init(autoPushTracking: Bool?, autoTokenForwardingDisabled: Bool?) {
        var values = [SdkFeatureKey: Bool]()
        values[.autoPushTracking] = autoPushTracking
        // Report each flag's configured state independently. Token forwarding is considered enabled
        // unless the escape hatch explicitly disables it; this is decoupled from the master flag so we
        // capture how the host set each flag rather than a collapsed runtime state.
        values[.autoPushTokenForwarding] = autoTokenForwardingDisabled.map { !$0 }
        self.init(values: values)
    }

    /// The configured state of a feature, or `nil` when the host never set it (the feature is
    /// then omitted from the header, so the backend must treat its absence as "unknown", not `false`).
    public subscript(featureKey: SdkFeatureKey) -> Bool? {
        values[featureKey]
    }

    /// Value for the `X-Klaviyo-Sdk-Features` header on requests in the given scope, e.g.
    /// `auto_push_tracking=1; auto_push_token_forwarding=0;`. Only configured features belonging
    /// to the scope are included; returns `nil` when there are none, so callers omit the header.
    public func headerValue(for scope: SdkFeatureScope) -> String? {
        let fields = SdkFeatureKey.allCases
            .filter { $0.scope == scope }
            .compactMap { featureKey in values[featureKey].map { "\(featureKey.rawValue)=\($0 ? 1 : 0)" } }
        return fields.isEmpty ? nil : fields.joined(separator: "; ") + ";"
    }
}
