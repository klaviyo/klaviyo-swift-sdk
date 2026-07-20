//
//  UInt64+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/10/25.
//

import Foundation

extension UInt64 {
    package var seconds: TimeInterval {
        Double(self) / 1_000_000_000
    }

    package var milliseconds: TimeInterval {
        Double(self) / 1_000_000
    }

    package var microseconds: TimeInterval {
        Double(self) / 1000
    }

    package var nanoseconds: TimeInterval {
        Double(self)
    }
}
