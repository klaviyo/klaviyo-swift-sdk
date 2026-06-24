//
//  FlushGovernorConfig.swift
//
//  Runtime configuration for the demand-adaptive flush governor.
//
//  Copyright (c) 2026 Klaviyo
//  Licensed under the MIT License. See LICENSE file in the project root for full license information.
//

import Foundation

/// Runtime switches for the demand-adaptive flush governor (token-bucket gate +
/// queue-depth early-flush trigger).
///
/// This exists so we can:
/// - A/B the governor against the legacy fixed-interval flush behavior on the same build
///   (flip `isEnabled` between runs and compare request timing / 429 rate), and
/// - disable the new behavior at runtime as a kill switch if it ever misbehaves in the field.
///
/// When `isEnabled` is `false` the reducer skips the token-bucket gate and the queue-depth
/// trigger entirely, reproducing the previous "flush the whole queue on every interval tick"
/// behavior.
enum FlushGovernorConfig {
    static var isEnabled = true
}
