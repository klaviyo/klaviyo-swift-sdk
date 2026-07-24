//
//  FlushGovernorConfig.swift
//
//  Runtime configuration for the demand-adaptive flush governor.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation

/// Internal experiment toggle for the demand-adaptive flush governor (token-bucket gate +
/// queue-depth early-flush trigger).
///
/// `isEnabled` is intentionally `internal`, not `public` — host apps cannot flip this from
/// outside the SDK. It exists so Klaviyo engineers can A/B the governor against the legacy
/// fixed-interval flush behavior from test targets or internal debug builds (flip `isEnabled`
/// and compare request timing / 429 rate). It is not a field-facing kill switch, and it must be
/// set before the SDK initializes and left untouched for the rest of the process's lifetime —
/// toggling it mid-session is unsupported, since the token bucket assumes a stable governor
/// state.
///
/// When `isEnabled` is `false` the reducer skips the token-bucket gate and the queue-depth
/// trigger entirely, reproducing the previous "flush the whole queue on every interval tick"
/// behavior.
enum FlushGovernorConfig {
    static var isEnabled = true
}
