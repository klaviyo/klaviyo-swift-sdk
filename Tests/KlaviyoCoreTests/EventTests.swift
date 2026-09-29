//
//  EventTests.swift
//
//
//  Created by Andrew Balmer on 9/3/24.
//

@testable import KlaviyoCore
import Foundation
import XCTest

class KlaviyoEventTests: XCTestCase {
    func testOpenedPushEvent() {
        let openedPushEvent = Event.EventName._openedPush
        XCTAssertEqual(openedPushEvent, .customEvent("_openedPush"))
    }

    func testEventNameValueMapping() {
        XCTAssertEqual(Event.EventName._openedPush.value, "$opened_push")
        XCTAssertEqual(Event.EventName.openedAppMetric.value, "Opened App")
        XCTAssertEqual(Event.EventName.viewedProductMetric.value, "Viewed Product")
        XCTAssertEqual(Event.EventName.addedToCartMetric.value, "Added to Cart")
        XCTAssertEqual(Event.EventName.startedCheckoutMetric.value, "Started Checkout")
        XCTAssertEqual(Event.EventName.locationEvent(.geofenceEnter).value, "$geofence_enter")
        XCTAssertEqual(Event.EventName.locationEvent(.geofenceExit).value, "$geofence_exit")
        XCTAssertEqual(Event.EventName.locationEvent(.geofenceDwell).value, "$geofence_dwell")
        XCTAssertEqual(Event.EventName.customEvent("Custom Metric").value, "Custom Metric")
    }

    func testGeofenceEventDetection() {
        XCTAssertTrue(Event.Metric(name: .locationEvent(.geofenceEnter)).isGeofenceEvent)
        XCTAssertFalse(Event.Metric(name: .openedAppMetric).isGeofenceEvent)
    }
}
