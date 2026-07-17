//
// EventTests.swift
// Klaviyo Swift SDK
//
// Copyright © 2026 Klaviyo, Inc. Licensed under the MIT License.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

class KlaviyoEventTests: XCTestCase {
    func testOpenedPushEvent() {
        let openedPushEvent = Event.EventName._openedPush
        XCTAssertEqual(openedPushEvent, .customEvent("_openedPush"))
    }
}
