//
//  InboxLimits.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

package enum InboxLimits {
    package static let retentionRange = 1...500
    package static let defaultRetention = 100

    package static func clampedRetention(_ requested: Int) -> Int {
        min(max(requested, retentionRange.lowerBound), retentionRange.upperBound)
    }
}
