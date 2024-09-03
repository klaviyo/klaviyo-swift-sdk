//
//  EventTests.swift
//
//
//  Created by Andrew Balmer on 9/3/24.
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
