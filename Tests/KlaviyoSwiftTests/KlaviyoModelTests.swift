//
//  File.swift
//
//
//  Created by Noah Durell on 12/19/23.
//

@testable import KlaviyoSwift
import Foundation
import XCTest

class KlaviyoModelTests: XCTestCase {
    func testMetricNameEquality() {
        let metric1 = Event.Metric(metricName: Event.V1.MetricName.OpenedApp)
        let metric2 = Event.Metric(metricName: Event.Legacy.MetricName.OpenedApp)
        XCTAssertNotEqual(metric1, metric2)

        let metric3 = Event.Metric(metricName: Event.V1.MetricName.CustomEvent("foo"))
        let metric4 = Event.Metric(metricName: Event.Legacy.MetricName.CustomEvent("foo"))
        XCTAssertNotEqual(metric3, metric4)

        let metric5 = Event.Metric(metricName: Event.V1.MetricName.CustomEvent("foo"))
        let metric6 = Event.Metric(metricName: Event.V1.MetricName.CustomEvent("foo"))
        XCTAssertEqual(metric5, metric6)
    }
}
