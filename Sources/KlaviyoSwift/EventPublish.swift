//
//  EventPublish.swift
//  klaviyo-swift-sdk
//

import KlaviyoCore

/// Enriches an event with device/SDK metadata and pushes it to the `KlaviyoCore` `EventBus`.
/// KlaviyoSwift's write-side push of observed events into KlaviyoCore. Called from the reducer.
func enrichAndPublishEvent(_ event: Event) {
    EventBus.shared.publish(enrichEventWithMetadata(event))
}

/// Returns a copy of `event` with device/SDK/app metadata appended to its properties.
private func enrichEventWithMetadata(_ event: Event) -> Event {
    let enrichedProperties = event.properties.appendMetadataToProperties() ?? event.properties
    return Event(
        name: event.metric.name,
        properties: enrichedProperties,
        identifiers: event.identifiers,
        value: event.value,
        time: event.time,
        uniqueId: event.uniqueId
    )
}
