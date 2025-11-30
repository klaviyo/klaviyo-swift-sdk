# KlaviyoLocation Integration Guide

## Overview

This document outlines how to integrate ProfileDataStore into KlaviyoLocation once the `feat/geofencing` branch is merged. The implementation decouples KlaviyoLocation from KlaviyoSwift by using the shared ProfileDataStore in KlaviyoCore.

**Note:** KlaviyoLocation does not exist on the `master` branch yet. These changes should be applied after merging `feat/geofencing`.

---

## Phase 3: Create GeofenceEventBuffer

### File: `Sources/KlaviyoLocation/GeofenceEventBuffer.swift` (NEW)

```swift
//
//  GeofenceEventBuffer.swift
//  KlaviyoLocation
//
//  Created for ProfileDataStore Integration
//

import Foundation
import KlaviyoCore

/// Buffers geofence events and sends them when profile data becomes available.
///
/// This buffer allows geofence events to be captured even before the SDK is
/// fully initialized. Events are persisted to disk and automatically flushed
/// when profile data becomes available.
class GeofenceEventBuffer {
    static let shared = GeofenceEventBuffer()

    private var bufferedEvents: [BufferedEvent] = []
    private let maxBufferSize = 100
    private let bufferFileName = "klaviyo-location-buffer.json"
    private var flushTimer: Timer?

    struct BufferedEvent: Codable {
        let eventType: String  // "$geofence_enter", "$geofence_exit", "$geofence_dwell"
        let locationId: String
        let timestamp: Date
    }

    private init() {
        loadBufferedEventsFromDisk()
        startPeriodicFlushAttempts()
    }

    // MARK: - Public API

    /// Buffers a geofence event and attempts to send it immediately if profile is available.
    func buffer(eventType: String, locationId: String) {
        let event = BufferedEvent(
            eventType: eventType,
            locationId: locationId,
            timestamp: Date()
        )

        // Try immediate send if profile available
        if let profile = ProfileDataStore.loadCurrent(), profile.isValid {
            send(event, with: profile)
            return
        }

        // Otherwise buffer it
        addToBuffer(event)
        persistBuffer()
    }

    // MARK: - Private Methods

    private func addToBuffer(_ event: BufferedEvent) {
        // FIFO: remove oldest if at capacity
        if bufferedEvents.count >= maxBufferSize {
            bufferedEvents.removeFirst()
        }
        bufferedEvents.append(event)
    }

    private func send(_ event: BufferedEvent, with profile: ProfileDataStore) {
        guard let apiKey = profile.apiKey else {
            environment.logger.error("Cannot send geofence event: API key missing")
            return
        }

        // Build event payload
        let payload = CreateEventPayload(
            data: CreateEventPayload.Event(
                type: "event",
                attributes: CreateEventPayload.Event.Attributes(
                    metric: CreateEventPayload.Metric(
                        data: CreateEventPayload.Metric.MetricPayload(
                            type: "metric",
                            attributes: CreateEventPayload.Metric.MetricPayload.Attributes(
                                name: event.eventType
                            )
                        )
                    ),
                    profile: CreateEventPayload.EventProfile(
                        data: CreateEventPayload.EventProfile.ProfileData(
                            type: "profile",
                            attributes: CreateEventPayload.EventProfile.ProfileData.Attributes(
                                email: profile.email,
                                phoneNumber: profile.phoneNumber,
                                externalId: profile.externalId,
                                anonymousId: profile.anonymousId
                            )
                        )
                    ),
                    properties: ["$geofence_id": event.locationId],
                    time: event.timestamp,
                    uniqueId: UUID().uuidString
                )
            )
        )

        let endpoint = KlaviyoEndpoint.createEvent(apiKey, payload)
        let request = KlaviyoRequest(endpoint: endpoint)

        // Send via KlaviyoCore networking
        Task {
            do {
                let attemptInfo = try RequestAttemptInfo(attemptNumber: 1, maxAttempts: 1)
                let result = await environment.klaviyoAPI.send(request, attemptInfo)

                switch result {
                case .success:
                    environment.logger.info("Geofence event sent successfully: \(event.eventType)")
                case .failure(let error):
                    environment.logger.error("Failed to send geofence event: \(error)")
                    // Could implement retry logic here
                }
            } catch {
                environment.logger.error("Error preparing geofence event request: \(error)")
            }
        }
    }

    private func flushBuffer() {
        guard !bufferedEvents.isEmpty else { return }

        guard let profile = ProfileDataStore.loadCurrent(), profile.isValid else {
            // Profile not ready yet, try again later
            return
        }

        // Send all buffered events
        let eventsToSend = bufferedEvents
        bufferedEvents.removeAll()
        clearPersistedBuffer()

        for event in eventsToSend {
            send(event, with: profile)
        }
    }

    private func startPeriodicFlushAttempts() {
        // Try to flush every 30 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flushBuffer()
        }
    }

    // MARK: - Persistence

    private func persistBuffer() {
        let file = bufferFile()
        do {
            let data = try JSONEncoder().encode(bufferedEvents)
            try environment.fileClient.write(data, file)
        } catch {
            environment.logger.error("Failed to persist event buffer: \(error)")
        }
    }

    private func loadBufferedEventsFromDisk() {
        let file = bufferFile()
        guard environment.fileClient.fileExists(file.path) else { return }

        guard let data = try? environment.dataFromUrl(file),
              let events = try? JSONDecoder().decode([BufferedEvent].self, from: data) else {
            // Corrupted buffer, remove it
            try? environment.fileClient.removeItem(file.path)
            return
        }

        bufferedEvents = events
        environment.logger.info("Loaded \(events.count) buffered geofence events from disk")

        // Try to flush immediately
        flushBuffer()
    }

    private func clearPersistedBuffer() {
        let file = bufferFile()
        try? environment.fileClient.removeItem(file.path)
    }

    private func bufferFile() -> URL {
        let directory = environment.fileClient.libraryDirectory()
        return directory.appendingPathComponent(bufferFileName, isDirectory: false)
    }
}
```

---

## Phase 4: Refactor KlaviyoLocation Files

### 1. Update `KlaviyoLocationManager+CLLocationManagerDelegate.swift`

**Before:**
```swift
import KlaviyoSwift  // ❌ Remove this

private func handleGeofenceEvent(region: CLRegion, eventType: Event.EventName.LocationEvent) {
    let event = Event(
        name: .locationEvent(eventType),
        properties: ["$geofence_id": klaviyoLocationId]
    )

    Task {
        await MainActor.run {
            KlaviyoInternal.create(event: event)  // ❌ Tight coupling
        }
    }
}
```

**After:**
```swift
import KlaviyoCore  // ✅ Only Core dependency

private func handleGeofenceEvent(region: CLRegion, eventType: LocationEventType) {
    guard let geofence = parseGeofence(from: region) else { return }

    let eventName: String
    switch eventType {
    case .enter:
        eventName = "$geofence_enter"
    case .exit:
        eventName = "$geofence_exit"
    case .dwell:
        eventName = "$geofence_dwell"
    }

    GeofenceEventBuffer.shared.buffer(
        eventType: eventName,
        locationId: geofence.locationId
    )
}
```

### 2. Update `KlaviyoLocationManager.swift`

**Before:**
```swift
func syncGeofences() async {
    guard let apiKey = try? await KlaviyoInternal.fetchAPIKey() else {  // ❌ Coupling
        return
    }
    // ... fetch geofences
}
```

**After:**
```swift
func syncGeofences() async {
    guard let profile = ProfileDataStore.loadCurrent(),
          let apiKey = profile.apiKey else {  // ✅ Uses ProfileDataStore
        environment.logger.info("SDK not initialized, skipping geofence refresh")
        return
    }
    // ... fetch geofences
}
```

**Before:**
```swift
private func startObservingAPIKeyChanges() {
    apiKeyCancellable = KlaviyoInternal.apiKeyPublisher()  // ❌ Coupling
        .sink { [weak self] result in
            // ...
        }
}
```

**After:**
```swift
private func startObservingAPIKeyChanges() {
    // Poll ProfileDataStore every 30 seconds for API key changes
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        if let profile = ProfileDataStore.loadCurrent(),
           let apiKey = profile.apiKey {
            self?.handleAPIKeyChange(apiKey)
        }
    }
}
```

### 3. Update `GeofenceService.swift`

**No major changes needed** - already uses KlaviyoCore networking.

Just ensure it accepts apiKey as parameter rather than fetching from KlaviyoInternal.

---

## Phase 5: Remove KlaviyoSwift Imports

**Files to Update:**
1. `Sources/KlaviyoLocation/KlaviyoLocationManager.swift`
2. `Sources/KlaviyoLocation/KlaviyoLocationManager+CLLocationManagerDelegate.swift`
3. `Sources/KlaviyoLocation/KlaviyoSDK+Location.swift` (if exists)

**Change:**
```swift
import KlaviyoSwift  // ❌ Remove
```

**To:**
```swift
import KlaviyoCore   // ✅ Only Core
```

---

## Testing the Integration

### Unit Tests

**File: `Tests/KlaviyoLocationTests/GeofenceEventBufferTests.swift`** (NEW)

```swift
import XCTest
@testable import KlaviyoLocation
@testable import KlaviyoCore

class GeofenceEventBufferTests: XCTestCase {
    func testBufferEventWhenProfileNotAvailable() {
        // Given: No profile available
        ProfileDataStore.remove(apiKey: "test-key")

        // When: Buffer an event
        GeofenceEventBuffer.shared.buffer(eventType: "$geofence_enter", locationId: "loc-123")

        // Then: Event should be in buffer
        // (check buffer persistence file exists)
    }

    func testFlushBufferWhenProfileBecomesAvailable() {
        // Given: Events in buffer
        GeofenceEventBuffer.shared.buffer(eventType: "$geofence_enter", locationId: "loc-123")

        // When: Profile becomes available
        let profile = ProfileDataStore(
            apiKey: "test-key",
            anonymousId: "user-123",
            email: "test@example.com"
        )
        ProfileDataStore.save(profile)

        // Then: Buffer should flush
        // (verify network request made, buffer cleared)
    }
}
```

### Integration Tests

1. **Test: Geofence fires before SDK initialization**
   - App launches in background
   - Geofence triggers
   - Verify event buffered
   - SDK initializes
   - Verify event sent

2. **Test: Geofence fires after SDK initialization**
   - SDK already initialized
   - Geofence triggers
   - Verify event sent immediately

3. **Test: Profile updates propagate**
   - SDK initialized with email A
   - User updates to email B
   - Geofence triggers
   - Verify event sent with email B

---

## Migration Checklist

- [ ] Merge `feat/geofencing` branch to get KlaviyoLocation code
- [ ] Create `GeofenceEventBuffer.swift`
- [ ] Update `KlaviyoLocationManager+CLLocationManagerDelegate.swift`
- [ ] Update `KlaviyoLocationManager.swift`
- [ ] Remove all `import KlaviyoSwift` from KlaviyoLocation
- [ ] Add unit tests for GeofenceEventBuffer
- [ ] Add integration tests
- [ ] Verify builds successfully
- [ ] Test in simulator (geofence scenarios)
- [ ] Test on device (background scenarios)

---

## Benefits After Integration

✅ **Decoupled Architecture:** KlaviyoLocation → KlaviyoCore (no KlaviyoSwift dependency)
✅ **Background Support:** Geofence events work when app terminated
✅ **No Lost Events:** Buffering ensures events captured before SDK init
✅ **Profile Accuracy:** Single source of truth via dual-write
✅ **Clean Module Boundaries:** Each module depends only on Core

---

## Future Enhancements

1. **Smarter Retry Logic:** Exponential backoff for failed event sends
2. **Network Awareness:** Only flush when network available
3. **Event Deduplication:** Prevent duplicate events if sent multiple times
4. **Analytics:** Track buffer size, flush success rate, etc.
5. **Configuration:** Make buffer size and flush interval configurable

---

## Questions or Issues?

If you encounter any issues during integration, check:
1. ProfileDataStore file exists: `klaviyo-{apiKey}-profile.json`
2. Buffer file exists: `klaviyo-location-buffer.json`
3. Logs for ProfileDataStore save/load operations
4. Network requests being made with correct profile data
