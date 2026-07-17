//
// UInt64+Ext.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

import Foundation

package extension UInt64 {
    var seconds: TimeInterval { Double(self) / 1_000_000_000 }
    var milliseconds: TimeInterval { Double(self) / 1_000_000 }
    var microseconds: TimeInterval { Double(self) / 1000 }
    var nanoseconds: TimeInterval { Double(self) }
}
