//
//  EncodableTests.swift
//
//
//  Created by Ajay Subramanya on 8/15/24.
//

import Foundation

@testable import KlaviyoCore
@testable import KlaviyoSwift
import SnapshotTesting
import XCTest

final class EncodableTests: XCTestCase {
    let testEncoder = KlaviyoEnvironment.encoder

    override func setUpWithError() throws {
        environment = KlaviyoEnvironment.test()
        testEncoder.outputFormatting = .prettyPrinted.union(.sortedKeys)
    }

    // NOTE: the former `testKlaviyoState` snapshot verified the queue-only state blob's JSON.
    // `KlaviyoState` is no longer `Codable` (removed in Task 5) — the queue backing moved to the
    // Core `QueueStore` which owns its own persistence. No state-blob encoding to snapshot here.
}
