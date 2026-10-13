//
//  InboxLimitsTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInboxCore

#if canImport(Testing)
import Testing

struct InboxLimitsTests {
    @Test(arguments: [
        (Int.min, 1), (-5, 1), (0, 1), (1, 1), (100, 100), (500, 500), (501, 500), (Int.max, 500)
    ])
    func clampsToRange(requested: Int, expected: Int) {
        #expect(InboxLimits.clampedRetention(requested) == expected)
    }

    @Test
    func defaultIsInsideRange() {
        #expect(InboxLimits.defaultRetention == 100)
        #expect(InboxLimits.retentionRange.contains(InboxLimits.defaultRetention))
    }
}
#endif
