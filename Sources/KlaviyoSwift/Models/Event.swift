//
//  Event.swift
//  KlaviyoSwift
//

import KlaviyoCore

/// An event to track for the current profile with ``KlaviyoSDK/create(event:)``.
///
/// Create an event with a predefined metric or a custom name, plus optional properties and value:
///
/// ```swift
/// let event = Event(
///     name: .customEvent("Completed Onboarding"),
///     properties: ["Step Count": 4]
/// )
/// KlaviyoSDK().create(event: event)
/// ```
///
/// Predefined product metrics are `.openedAppMetric`, `.viewedProductMetric`,
/// `.addedToCartMetric` and `.startedCheckoutMetric`; use `.customEvent(_:)` for any other name.
/// The SDK tracks `.locationEvent(_:)` itself for geofencing. The initializer is
/// `init(name:properties:value:valueCurrency:uniqueId:)`. `value` is a monetary amount, such as an
/// order total, in the ISO 4217 currency named by `valueCurrency`. Klaviyo deduplicates
/// events that share a `uniqueId`; the SDK generates one if you omit it.
///
/// `Event` is defined in `KlaviyoCore` and re-exported here, so you only need to import
/// `KlaviyoSwift`.
public typealias Event = KlaviyoCore.Event
