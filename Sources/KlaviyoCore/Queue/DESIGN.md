# KlaviyoCore Networking & Queueing System Design

**Status**: ✅ Implementation Complete
**Branch**: `feat/core-networking`
**Author**: Claude Code
**Date**: 2025-11-10

## Implementation Summary

The new networking and queueing system is now fully implemented with the following components:

### ✅ Implemented Components

1. **QueueConfiguration** (`Queue/QueueConfiguration.swift`)
   - Configurable queue parameters (max size, retries, intervals, backoff)
   - Default configuration matching existing KlaviyoSwift behavior
   - Test configuration for faster testing

2. **QueuedRequest** (`Queue/QueuedRequest.swift`)
   - Wrapper around KlaviyoRequest with retry state
   - Tracks retry count, creation time, and backoff expiration
   - Helper methods for retry and backoff management

3. **RequestQueue** (`Queue/RequestQueue.swift`)
   - Actor-based thread-safe queue
   - Dual-priority queues (immediate + normal)
   - FIFO ordering within each priority
   - Max queue size enforcement for normal queue
   - In-flight request tracking
   - Backoff support

4. **QueuePersistence** (`Queue/QueuePersistence.swift`)
   - JSON-based persistence to disk
   - File format: `klaviyo-{apiKey}-queue-v2.json`
   - Save/load/clear operations
   - Validation and error recovery

5. **QueueProcessor** (`Queue/QueueProcessor.swift`)
   - Background processing actor
   - Start/pause/resume/stop lifecycle
   - Retry logic with exponential backoff
   - Max retries enforcement
   - Error categorization (network, rate limit, HTTP 4xx/5xx)
   - Automatic persistence on queue changes

6. **NetworkingClient** (`Networking/NetworkingClient.swift`)
   - Public API facade
   - Singleton pattern with configuration
   - Immediate send (bypass queue)
   - Enqueue (fire-and-forget)
   - Queue management (start/pause/resume/stop/flush)
   - State access for debugging

### ✅ Test Coverage

Comprehensive test suites written for all components:

1. **RequestQueueTests** (25+ tests)
   - Enqueue/dequeue operations
   - Priority ordering
   - Max queue size
   - In-flight tracking
   - Backoff behavior
   - Persistence helpers

2. **QueuePersistenceTests** (15+ tests)
   - Save/load operations
   - Error handling (corrupt files, API key mismatch)
   - Backoff persistence
   - File existence checks

3. **QueueProcessorTests** (15+ tests)
   - Start/stop/pause/resume lifecycle
   - Success and failure flows
   - Retry logic for different error types
   - Max retries enforcement
   - Backoff timing
   - Persistence integration

4. **NetworkingClientTests** (15+ tests)
   - Immediate send operations
   - Enqueue operations
   - Queue processing
   - Pause/resume behavior
   - State access
   - Persistence integration

### 📁 File Structure

```
Sources/KlaviyoCore/
├── Queue/
│   ├── DESIGN.md (this file)
│   ├── QueueConfiguration.swift
│   ├── QueuedRequest.swift
│   ├── RequestQueue.swift
│   ├── QueuePersistence.swift
│   └── QueueProcessor.swift
└── Networking/
    └── NetworkingClient.swift

Tests/KlaviyoCoreTests/Queue/
├── RequestQueueTests.swift
├── QueuePersistenceTests.swift
├── QueueProcessorTests.swift
└── NetworkingClientTests.swift
```

### 🚀 Ready for Integration

The system is ready for integration with:
- ✅ KlaviyoForms (enqueue events)
- ✅ KlaviyoGeofence (immediate send)
- ⏳ KlaviyoSwift (future migration)

## Overview

This document describes the design and implementation of a general-purpose networking and queueing system in KlaviyoCore. This system decouples networking concerns from KlaviyoSwift, enabling reuse across multiple SDK modules (KlaviyoForms, KlaviyoGeofence, and eventually KlaviyoSwift itself).

## Goals

1. **Separation of Concerns**: Move networking and queueing logic from KlaviyoSwift to KlaviyoCore
2. **Reusability**: Enable KlaviyoForms and KlaviyoGeofence to use the same networking infrastructure
3. **Priority Support**: Support immediate (bypass queue) and normal (queued) request execution
4. **Backward Compatibility**: Don't break existing KlaviyoSwift queue during migration
5. **Incremental Migration**: Start with Forms/Geofence, migrate KlaviyoSwift later

## Non-Goals (For Now)

- Request batching (send one at a time, like current system)
- Complex priority levels (just immediate vs normal)
- Breaking changes to existing KlaviyoSwift queue

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     KlaviyoCore                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  NetworkingClient (Public API)                              │
│    ├─→ send() - Immediate execution (bypass queue)          │
│    └─→ enqueue() - Queued execution                         │
│         ↓                                                    │
│  QueueProcessor (Worker)                                    │
│    ├─→ Continuously processes queue                         │
│    ├─→ Handles retries with backoff                         │
│    └─→ Integrates with lifecycle                            │
│         ↓                                                    │
│  RequestQueue (Actor)                                       │
│    ├─→ immediateQueue: [KlaviyoRequest]                     │
│    ├─→ normalQueue: [KlaviyoRequest]                        │
│    └─→ inFlight: Set<String> (request IDs)                  │
│         ↓                                                    │
│  QueuePersistence                                           │
│    ├─→ save() - Write to disk                               │
│    └─→ load() - Read from disk                              │
│         ↓                                                    │
│  KlaviyoAPI (Existing)                                      │
│    └─→ HTTP request execution                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. NetworkingClient (Public API)

**File**: `Sources/KlaviyoCore/Networking/NetworkingClient.swift`

Public facade for networking operations. This is the main entry point for other modules.

```swift
public struct NetworkingClient {
    /// Send request immediately, bypassing queue (for time-critical operations)
    /// - Returns: Response data or throws error
    public func send(_ request: KlaviyoRequest) async throws -> Data

    /// Enqueue request for later processing
    /// - Parameters:
    ///   - request: The request to enqueue
    ///   - priority: Queue priority (.immediate or .normal)
    public func enqueue(_ request: KlaviyoRequest, priority: RequestPriority = .normal)

    /// Start processing queued requests
    public func start()

    /// Pause queue processing (e.g., on app background)
    public func pause()

    /// Resume queue processing
    public func resume()

    /// Flush queue immediately
    public func flush()
}

public enum RequestPriority {
    case immediate  // High priority, dequeued first
    case normal     // Standard priority, FIFO
}
```

**Usage Examples**:

```swift
// Forms: Enqueue event (fire-and-forget)
let request = KlaviyoRequest(endpoint: .createEvent(event))
NetworkingClient.shared.enqueue(request, priority: .normal)

// Geofence: Immediate send (get result/error)
do {
    let response = try await NetworkingClient.shared.send(geofenceRequest)
    // Handle response
} catch {
    // Handle error
}
```

#### 2. QueueProcessor (Worker)

**File**: `Sources/KlaviyoCore/Queue/QueueProcessor.swift`

Background worker that continuously processes the queue. Runs asynchronously and handles:
- Dequeuing requests (immediate priority first)
- Executing via KlaviyoAPI
- Retry logic on failure
- Persistence on changes

```swift
actor QueueProcessor {
    private let queue: RequestQueue
    private let persistence: QueuePersistence
    private let api: KlaviyoAPIClient
    private var isProcessing = false
    private var isPaused = false

    func start()
    func pause()
    func resume()
    func flush()

    private func processLoop() async
    private func execute(_ request: KlaviyoRequest) async -> Result<Data, Error>
    private func handleFailure(_ request: KlaviyoRequest, _ error: Error) async
}
```

**Processing Loop**:

```
while isProcessing && !isPaused:
    1. Dequeue next request (immediate > normal)
    2. If queue empty, sleep briefly
    3. Execute request via KlaviyoAPI
    4. On success: Remove from queue, persist
    5. On failure: Apply retry logic
       - Network error → increment retry, re-queue
       - Rate limit → apply backoff, re-queue
       - HTTP 4xx → drop request
       - Max retries → drop request
    6. Persist queue state
    7. Continue loop
```

#### 3. RequestQueue (Actor)

**File**: `Sources/KlaviyoCore/Queue/RequestQueue.swift`

Thread-safe queue storage using Swift actors. Maintains two priority queues.

```swift
actor RequestQueue {
    private var immediateQueue: [KlaviyoRequest] = []
    private var normalQueue: [KlaviyoRequest] = []
    private var inFlight: Set<String> = []  // Request IDs currently processing
    private let configuration: QueueConfiguration

    // Enqueue
    func enqueue(_ request: KlaviyoRequest, immediate: Bool = false) async

    // Dequeue (immediate priority first, then normal FIFO)
    func dequeue() async -> KlaviyoRequest?

    // Mark as completed
    func complete(_ requestId: String) async

    // Handle failure (re-queue or drop)
    func fail(_ request: KlaviyoRequest, shouldRetry: Bool) async

    // Queue state
    var count: Int { get async }
    var isEmpty: Bool { get async }

    // For persistence
    func allRequests() async -> (immediate: [KlaviyoRequest], normal: [KlaviyoRequest])
    func restore(immediate: [KlaviyoRequest], normal: [KlaviyoRequest]) async
}
```

**Queue Limits**:
- Max queue size: 200 requests (configurable)
- Drops oldest normal-priority requests when full
- Immediate queue unlimited (or separate limit)

#### 4. QueuePersistence

**File**: `Sources/KlaviyoCore/Queue/QueuePersistence.swift`

Handles saving/loading queue to disk. Uses existing `FileClient` infrastructure.

```swift
struct QueuePersistence {
    let fileClient: FileClient
    let apiKey: String

    /// Save queue to disk
    func save(immediate: [KlaviyoRequest], normal: [KlaviyoRequest]) async throws

    /// Load queue from disk
    func load() async throws -> (immediate: [KlaviyoRequest], normal: [KlaviyoRequest])

    /// Clear persisted queue
    func clear() async throws

    private func queueFilePath() -> URL {
        // Returns: {libraryDir}/klaviyo-{apiKey}-queue-v2.json
    }
}
```

**File Format** (JSON):
```json
{
    "version": "2.0",
    "apiKey": "xyz",
    "immediate": [
        { "id": "uuid1", "endpoint": {...}, "retryCount": 0, "createdAt": "..." }
    ],
    "normal": [
        { "id": "uuid2", "endpoint": {...}, "retryCount": 2, "createdAt": "..." }
    ]
}
```

**Persistence Strategy**:
- Save after each queue modification (enqueue, dequeue, failure)
- Debounce? No - immediate consistency preferred
- Use atomic writes (via FileClient)
- Load on initialization

#### 5. QueueConfiguration

**File**: `Sources/KlaviyoCore/Queue/QueueConfiguration.swift`

Configuration for queue behavior.

```swift
struct QueueConfiguration {
    /// Maximum requests in normal queue
    let maxQueueSize: Int

    /// Maximum retry attempts per request
    let maxRetries: Int

    /// Flush interval (seconds) when processing
    let flushInterval: TimeInterval

    /// Maximum backoff duration (seconds)
    let maxBackoff: TimeInterval

    /// Default configuration
    static let `default` = QueueConfiguration(
        maxQueueSize: 200,
        maxRetries: 50,
        flushInterval: 10.0,
        maxBackoff: 180.0
    )
}
```

### Request Flow

#### Immediate Request (Geofence)

```
User Code
    ↓
NetworkingClient.send(request)
    ↓
[Bypass Queue]
    ↓
KlaviyoAPI.send(request, attemptInfo)
    ↓
URLSession HTTP call
    ↓
Success → Return Data
Failure → Throw Error (no retry, caller handles)
```

#### Queued Request (Forms)

```
User Code
    ↓
NetworkingClient.enqueue(request, .normal)
    ↓
RequestQueue.enqueue(request, immediate: false)
    ↓
normalQueue.append(request)
    ↓
QueuePersistence.save()
    ↓
[QueueProcessor detects new item]
    ↓
QueueProcessor.processLoop()
    ↓
RequestQueue.dequeue() → request
    ↓
Mark as inFlight
    ↓
KlaviyoAPI.send(request, attemptInfo)
    ↓
┌─── Success ───┐     ┌─── Failure ───┐
│ Complete      │     │ Apply Retry   │
│ Remove        │     │ Logic:        │
│ Persist       │     │ - Network →   │
│               │     │   re-queue    │
└───────────────┘     │ - Rate limit  │
                      │   → backoff   │
                      │ - 4xx → drop  │
                      │ - Max retries │
                      │   → drop      │
                      └───────────────┘
```

## Retry Logic

Reuses existing retry logic from KlaviyoSwift but adapted for the new system.

### Retry Categories

1. **Network Errors** (connection timeout, DNS failure, etc.)
   - Action: Increment retry count, re-queue
   - Delay: Immediate (next flush cycle)

2. **Rate Limit** (HTTP 429, 503)
   - Action: Apply exponential backoff
   - Delay: `2^attemptNumber + jitter` seconds (0-9s random)
   - Respects `Retry-After` header if present
   - Max backoff: 180 seconds

3. **HTTP 4xx Errors**
   - Action: Drop request (client error, non-retryable)
   - Special case: Invalid email/phone → Parse response, reset fields in request?

4. **Max Retries Exceeded**
   - Action: Drop request
   - Log warning

### Retry State

Each request tracks:
```swift
struct KlaviyoRequest {
    let id: String
    let endpoint: KlaviyoEndpoint
    var retryCount: Int = 0
    var backoffUntil: Date?  // Don't process until this time
    let createdAt: Date
}
```

## App Lifecycle Integration

The `NetworkingClient` needs to respond to app lifecycle events:

```swift
// App Foreground
NetworkingClient.shared.start()

// App Background
NetworkingClient.shared.pause()
// Queue persisted automatically

// App Terminate
// Queue already persisted, no-op

// Network Reachability Change
// WiFi → cellular: Continue (maybe adjust flush interval later)
// No network: Pause
// Network restored: Resume
```

**Integration Point**: TBD - either:
- KlaviyoCore publishes lifecycle events (already exists via `AppLifeCycleEvents`)
- Caller (Forms/Geofence) handles lifecycle and calls start/pause
- NetworkingClient subscribes internally to lifecycle events

**Recommendation**: NetworkingClient internally subscribes to `AppLifeCycleEvents` for autonomy.

## Migration Path

### Phase 1: Initial Implementation (This Branch)
- ✅ Implement new queue in KlaviyoCore
- ✅ Create NetworkingClient API
- ✅ Write comprehensive tests
- ✅ No integration with other modules yet

### Phase 2: KlaviyoForms Integration (Next Branch)
- Update KlaviyoForms to use `NetworkingClient.enqueue()`
- Remove direct calls to `KlaviyoSDK().create(event:)`
- Test in klaviyo-ios-test-app

### Phase 3: KlaviyoGeofence Integration (Separate Branch)
- Use `NetworkingClient.send()` for immediate geofence events
- Error handling in geofence logic

### Phase 4: KlaviyoSwift Migration (Future)
- Replace state machine queue with NetworkingClient
- Migrate existing persisted queue data
- Remove legacy queue code
- Update tests

### Persistence Migration

When KlaviyoSwift eventually migrates:

```swift
// On first launch with new system:
1. Check if old queue file exists: klaviyo-{apiKey}-state.json
2. Load old KlaviyoState
3. Extract queue: [KlaviyoRequest]
4. Enqueue all requests into new system
5. Save new queue: klaviyo-{apiKey}-queue-v2.json
6. Delete old queue from KlaviyoState (leave other state intact)
7. Continue normal operation
```

## Testing Strategy

### Unit Tests

1. **RequestQueue Tests**
   - Enqueue/dequeue operations
   - Priority ordering (immediate before normal)
   - FIFO within priority level
   - Max queue size enforcement
   - In-flight tracking

2. **QueuePersistence Tests**
   - Save/load queue
   - File format validation
   - Corrupt file handling
   - API key mismatch

3. **QueueProcessor Tests**
   - Processing loop behavior
   - Retry logic (network errors, rate limits)
   - Max retries enforcement
   - Backoff timing
   - Pause/resume behavior

4. **NetworkingClient Tests**
   - Public API contracts
   - Immediate vs queued execution
   - Error propagation
   - Lifecycle integration

### Integration Tests

1. **End-to-End Flow**
   - Enqueue → Process → Complete
   - Enqueue → Process → Fail → Retry → Complete
   - Immediate send with success/failure

2. **Persistence Integration**
   - Enqueue → Persist → App restart → Load → Process
   - Queue state preserved across restarts

3. **Lifecycle Integration**
   - Pause on background → Resume on foreground
   - Persist on background

## Open Questions

1. ~~Should NetworkingClient be a singleton or instance-based?~~
   - **Decision**: Singleton (`NetworkingClient.shared`) for simplicity
   - Requires initialization with API key

2. ~~How to handle API key changes mid-session?~~
   - **Decision**: Not handled in this system - caller's responsibility
   - Forms/Geofence don't change API keys mid-session
   - KlaviyoSwift handles this at higher level

3. ~~Should immediate requests still be tracked in queue for observability?~~
   - **Decision**: No - completely bypass queue
   - Tracked only via existing `SDKRequestIterator` mechanism

4. ~~Flush interval: Fixed or adaptive (WiFi vs cellular)?~~
   - **Decision**: Fixed for MVP (10s)
   - Can add adaptive later

5. ~~Should QueueProcessor use a timer or async sleep?~~
   - **Decision**: Async sleep in loop (more flexible)
   - Timer for future if needed

## Performance Considerations

- **Memory**: Queue size capped at 200 requests
- **Disk I/O**: Save after each queue change (atomic writes)
- **CPU**: Minimal - async processing, no tight loops
- **Network**: Sequential requests (no batching), respects rate limits
- **Thread Safety**: Actor-based, no locks needed

## Security Considerations

- **API Key**: Stored in persisted queue file (same as current system)
- **PII**: Events may contain PII (email, phone) - encrypted at rest? (No change from current)
- **File Permissions**: Use secure file attributes (via FileClient)

## Future Enhancements

1. **Batching**: Combine multiple events into single request
2. **Adaptive Intervals**: Adjust flush based on network type (WiFi vs cellular)
3. **Network Monitoring**: Integrate with `Reachability` for pause/resume
4. **Metrics**: Expose queue metrics (size, success rate, etc.)
5. **Priority Levels**: Add high/medium/low instead of just immediate/normal
6. **Request Compression**: Gzip large payloads
7. **Background URLSession**: Use background configuration for reliability

## References

- Existing queue: `Sources/KlaviyoSwift/StateManagement/KlaviyoState.swift`
- Retry logic: `Sources/KlaviyoSwift/StateManagement/APIRequestErrorHandling.swift`
- Networking: `Sources/KlaviyoCore/Networking/KlaviyoAPI.swift`
- File utilities: `Sources/KlaviyoCore/Utils/FileUtils.swift`
- Lifecycle events: `Sources/KlaviyoCore/AppLifeCycleEvents.swift`
