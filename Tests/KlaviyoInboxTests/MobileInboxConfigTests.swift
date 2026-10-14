//
//  MobileInboxConfigTests.swift
//  klaviyo-swift-sdk
//
//  Created by Isobelle Lim on 10/2/26.
//

import KlaviyoInbox

#if canImport(Testing)
import Testing

struct MobileInboxConfigTests {
    @Test
    func defaultRetentionIs100() {
        #expect(MobileInboxConfig.defaultLocalRetentionLimit == 100)
        #expect(MobileInboxConfig().localRetentionLimit == 100)
    }

    @Test(arguments: [(1, 1), (20, 20), (500, 500), (0, 1), (-3, 1), (501, 500)])
    func retentionLimitIsClampedToRange(requested: Int, expected: Int) {
        #expect(MobileInboxConfig(localRetentionLimit: requested).localRetentionLimit == expected)
    }

    @Test(arguments: [(5, 5, true), (5, 6, false)])
    func equatable(lhs: Int, rhs: Int, isEqual: Bool) {
        let result = MobileInboxConfig(localRetentionLimit: lhs) == MobileInboxConfig(localRetentionLimit: rhs)
        #expect(result == isEqual)
    }
}
#endif
