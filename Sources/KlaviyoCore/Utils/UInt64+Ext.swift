//
//  UInt64+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 4/10/25.
//

import Foundation

package extension UInt64 {
    var seconds: TimeInterval { Double(self) / 1_000_000_000 }
    var milliseconds: TimeInterval { Double(self) / 1_000_000 }
    var microseconds: TimeInterval { Double(self) / 1000 }
    var nanoseconds: TimeInterval { Double(self) }
}
