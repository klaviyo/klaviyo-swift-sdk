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
/// ## Creating an event
///
/// `init(name:properties:value:valueCurrency:uniqueId:)` takes:
///
/// - `name`: The event's metric, as an `Event.EventName`. Required.
/// - `properties`: A `[String: Any]` dictionary of event details. Values must be encodable as
///   JSON. Defaults to no properties.
/// - `value`: A monetary amount, such as an order total, as a `Double`.
/// - `valueCurrency`: The ISO 4217 currency code for `value`, such as `"USD"`.
/// - `uniqueId`: An identifier for this occurrence of the event. Klaviyo deduplicates events that
///   share a `uniqueId`. If you omit it, the SDK generates a UUID.
///
/// The event's `time` is set when you create it.
///
/// ## Event names
///
/// `Event.EventName` names the metric the event is recorded under in Klaviyo:
///
/// | Case | Klaviyo metric |
/// | --- | --- |
/// | `.openedAppMetric` | `Opened App` |
/// | `.viewedProductMetric` | `Viewed Product` |
/// | `.addedToCartMetric` | `Added to Cart` |
/// | `.startedCheckoutMetric` | `Started Checkout` |
/// | `.customEvent(_:)` | The string you pass, such as `"Completed Onboarding"` |
/// | `.locationEvent(_:)` | `$geofence_enter` or `$geofence_exit` |
///
/// The SDK tracks `.locationEvent(_:)` events itself when geofencing is registered; you don't need
/// to create them. A name's `value` property returns its Klaviyo metric name as a `String`.
///
/// ## Reading an event
///
/// An `Event` is immutable. Its `metric.name`, `properties`, `time`, `value`, `valueCurrency` and
/// `uniqueId` properties return the values it was created with.
///
/// `Event` is defined in `KlaviyoCore` and re-exported here, so you only need to import
/// `KlaviyoSwift`.
public typealias Event = KlaviyoCore.Event
