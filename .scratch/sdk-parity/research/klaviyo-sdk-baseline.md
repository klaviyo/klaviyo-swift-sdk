# Klaviyo Swift SDK — engineering baseline (v5.4.1, `master` @ effec59)

What the SDK does today, with file references, so every ticket in the map argues from evidence
rather than impression. Read alongside `competitor-sdks.md`.

## 1. Architecture in one paragraph

A single vendored, trimmed copy of The Composable Architecture (`Sources/KlaviyoSwift/Vendor/ComposableArchitecture`,
~2.8k lines) drives one global `Store<KlaviyoState, KlaviyoAction>` that lives on the **main thread**.
Every public call (`create(event:)`, `set(email:)`, `set(profile:)`, ...) hops to main via
`dispatchOnMainThread` (`Klaviyo.swift:17`) and the reducer in `StateManagement.swift` mutates a
`KlaviyoState` value that holds identity, push-token data and the **outbound request queue**. Side
effects run as TCA effects (Combine publishers / `Task`s). `KlaviyoCore` exposes shared stores
(`IdentityStore`, `SDKConfigStore`, `EventBus`) that `KlaviyoForms` and `KlaviyoLocation` observe
without importing `KlaviyoSwift`.

## 2. Request queue, batching, flush

| Aspect | Today | Where |
|---|---|---|
| Queue shape | `[KlaviyoRequest]` where each element holds a fully-built `KlaviyoEndpoint` + payload structs (`AnyCodable` properties) | `KlaviyoState.swift:76`, `KlaviyoRequest.swift` |
| Capacity | 200; on overflow, O(n) scan for oldest `enqueuedAt` and evict | `StateManagementConstants.maxQueueSize`, `KlaviyoState.evictOldestIfAtCapacity` |
| Flush cadence | Combine `Timer` every 10 s on Wi-Fi / 30 s on cellular; `∞` when unreachable | `StateManagementConstants`, `.start`, `.networkConnectivityChanged` |
| Batching | **None.** One HTTP `POST /client/events/` per event, one per profile update, etc. | `KlaviyoEndpoint.path` |
| Send concurrency | **Strictly serial.** `.flushQueue` moves the whole queue to `requestsInFlight`; `.sendRequest` sends `requestsInFlight.first`, awaits, dequeues, repeats | `StateManagement.swift` `.flushQueue` / `.sendRequest` / `.deQueueCompletedResults` |
| Head-of-line blocking | A failing request at the head is re-inserted at the front and everything behind it waits; `retryState` is a single global value | `.requestFailed`, `.cancelInFlightRequests` |
| Priority | `$opened_push` and geofence events insert at index 0 and trigger an immediate flush | `.enqueueEvent` |
| Flush on background | **No.** `.backgrounded` → `.stop` → cancels the timer and in-flight requests and puts them back in the queue. Events tracked just before backgrounding wait for the next foreground + timer tick | `LifecycleEventsExtension.swift:12`, `.stop` |
| Flush on terminate | **No** (`.terminated` → `.stop`) | same |
| Background task / `BGTaskScheduler` | Not used | — |
| Dedup / idempotency | Events carry a `unique_id` (UUID) in the payload; no client-side dedup | `CreateEventPayload` |

## 3. Persistence

- Whole `KlaviyoState` (identity + push token + **entire queue with full payloads**) is JSON-encoded and
  written as one file `Library/klaviyo-<apiKey>-state.json` (`KlaviyoState.swift` `saveKlaviyoState`).
- Trigger: `StateChangePublisher` observes every store emission, `removeDuplicates()` over the full
  state (O(queue) `Equatable` compare of `AnyCodable` payloads, **on main**), then `debounce(1s)` on a
  global queue, then re-encodes and rewrites the **whole** file.
- Consequence: cost per state change is O(queue size) compare + O(queue size) encode + full-file write;
  and anything tracked < 1 s before a crash or a `SIGKILL` is lost (debounce, no flush-on-terminate).
- `loadKlaviyoStateFromDisk` decodes the whole file on init (off-main, inside a `.run` effect).

## 4. Networking

- Ephemeral `URLSession`, default timeouts (60 s request); `waitsForConnectivity` not set;
  `Accept-Encoding: br, gzip, deflate` set for responses, **no request-body compression**
  (`NetworkSession.swift`).
- Retry: network errors retry up to `maxRetries = 50` per request (!) at the flush cadence;
  429/5xx use `max(2^attempt, Retry-After)` capped at 300 s plus 0–10 s jitter, honouring `Retry-After`
  (`KlaviyoAPI.swift`, `APIRequestErrorHandling.swift`). 4xx other than 429 are dropped (with
  invalid-email/phone state reset).
- Reachability: vendored `ReachabilitySwift` (SCNetworkReachability, `Sources/KlaviyoCore/Vendor`);
  `NWPathMonitor` is not used. Reachability is started/stopped on foreground/background.
- Payload weight: every event payload embeds the profile identifiers block and a `unique_id`;
  every push-token payload embeds full `device_metadata`; `EventBus` enrichment adds 12 metadata
  keys to properties before forwarding to Forms (`Dictionary+Metadata.swift`) — not sent to the API,
  but computed per event.
- `X-Klaviyo-Attempt-Count`, `revision`, `User-Agent` headers per request.

## 5. Startup / init latency and main-thread work

- `initialize(with:)` → `DispatchQueue.main.async { SharedStoreMirror.setup(); send(.initialize) }`
  → reducer sets `.initializing` → `.run { loadKlaviyoStateFromDisk }` (off-main) →
  `.completeInitialization` (main) replays `pendingRequests`, subscribes lifecycle + reachability +
  state-persistence publishers, then `.start` reads notification settings and starts the flush timer.
- Calls between init and complete are buffered in `pendingRequests`; calls before init are dropped with a
  developer warning (except auto push token, `$opened_push`, geofence events).
- **All reducer work is on main**: payload struct construction, `AnyCodable` wrapping, queue eviction
  scan, state `Equatable` diffing for three subscribers (`StateChangePublisher`, `SharedStoreMirror`,
  TCA `Store` itself). For an app that tracks a burst of events on scroll, this is UI-thread time.
- `AppContextInfo()` is constructed on demand (`environment.appContextInfo()` in
  `PushTokenPayload.MetaData.init`, `shouldSendTokenUpdate`, `appendMetadataToProperties`,
  `defaultUserAgent`). Its initializer reads `UIDevice.current.identifierForVendor` **and parses
  `embedded.mobileprovision` with a `Scanner`** to derive `aps-environment` (`AppContextInfo.swift`
  `pushEnvironment`) — file I/O + string scan on every construction, i.e. per event enrichment and per
  token comparison. Only the static `default*` values are cached.
- Notification-center delegate proxy is installed synchronously on main during `initialize`.

## 6. Threading / concurrency model

- Mixed: TCA effects (Combine), `Task {}` hops, `DispatchQueue.main.async`, GCD barrier queue in
  `EventBuffer`, `NSLock` in `AutomaticPushTokenSequence`, `@MainActor` on Forms types.
- No `-strict-concurrency`, no Swift 6 language mode; `swift-tools-version: 5.9`; iOS 13 minimum.
- Public `environment` is a global mutable `var` (`KlaviyoEnvironment.swift:14`) — convenient for tests,
  but a data-race surface under strict concurrency.

## 7. Dependencies & footprint

- Runtime third-party: `AnyCodable` (Flight-School) only. Vendored: TCA subset, ReachabilitySwift.
- Test-only: swift-snapshot-testing, swift-custom-dump, swift-case-paths, combine-schedulers.
- Distribution: source via SPM + CocoaPods (5 podspecs). No xcframework, no published size numbers,
  no size CI check. Privacy manifest present (`PrivacyInfo.xcprivacy`, tracking = false).
- Products: `KlaviyoSwift`, `KlaviyoForms`, `KlaviyoLocation`, `KlaviyoSwiftExtension` (+ internal
  `KlaviyoCore`, `KlaviyoAutomaticPushBootstrap`).

## 8. In-App Forms architecture (KlaviyoForms)

The decision engine is **the web onsite engine running inside a hidden `WKWebView`**:

1. `registerForInAppForms()` → `IAFPresentationManager.initializeIAF` (main actor). When an API key is
   observed, `createFormWebView` builds `IAFWebViewModel` + `KlaviyoWebViewController` around a
   `WKWebView` (`KlaviyoWebViewController.swift` `createDefaultWebView`) with
   `inactiveSchedulingPolicy = .none` on iOS 17+ (so the WebContent process is never throttled).
2. The webview loads a local `InAppFormsTemplate.html` that injects **`klaviyo.js` from the CDN**
   (`/onsite/js/klaviyo.js?company_id=…&env=in-app`) plus a CSS from `static-forms.klaviyo.com`
   (`IAFWebViewModel.klaviyoJsWKScript`). Forms definitions/targeting/assets are then fetched by
   klaviyo.js inside the webview.
3. Native waits for a JS `handShook` bridge message with a **single 10 s timeout**
   (`NetworkSession.networkTimeout`). On timeout it calls `destroyWebviewAndListeners()`, which sets
   `isInitializingOrInitialized = false` and drops the lifecycle observer — **forms stay off for the
   rest of the process** until the host calls `registerForInAppForms()` again.
4. After handshake, every SDK event is forwarded into JS via `evaluateJavaScript("dispatchProfileEvent(...)")`
   (`handleProfileEventCreated`), and profile identity changes are pushed as a `data-klaviyo-profile`
   attribute. Trigger evaluation happens in JS.
5. JS emits `formWillAppear(layout)`; native presents the **same** webview either as a full-screen
   modal on the top view controller or inside a dedicated `UIWindow` for banner/flexible layouts
   (`InAppWindowManager`). One webview ⇒ at most one form at a time; queuing/priority live in JS.
6. Session: `InAppFormsConfig.sessionTimeoutDuration` (default 3600 s). On foreground after a
   longer background, the webview is torn down and recreated → klaviyo.js + forms data reload.

Implications worth measuring before deciding anything:

- **Memory**: a live WebContent process for the whole app session even when no form ever shows.
- **Network / latency**: klaviyo.js + fonts CSS + forms data fetched per session (subject only to
  WebKit's HTTP cache); time-to-handshake bounds how early an "on app open" form can appear.
- **Reliability**: one slow cold start (>10 s to handshake) disables forms for the process.
- **Offline**: no native cache of form definitions or assets; nothing can show offline.
- **Control**: display rules (frequency caps, priority, per-session limits) are opaque to the native
  SDK and to host apps beyond the lifecycle handler.

## 9. Location & push extension (brief)

- Geofences: fetched via the queue-less path (`GeofenceService`), 20-region iOS cap handled,
  re-synced on API-key and lifecycle changes.
- NSE (`KlaviyoSwiftExtension`): downloads rich media with `URLSession`, badge via App Group
  `UserDefaults`, dynamic action-button categories. No `KlaviyoCore` dependency (extension-safe).

## 10. Test & CI surface

- 79 test files across 5 targets; snapshot tests for payloads; no performance tests (`measure`/
  `XCTMetric`) and no binary-size or memory regression check in `.github/workflows/swift.yml`.

## 11. Public API contract (what "don't change too many contracts" protects)

`KlaviyoSDK()` value type with chainable `initialize(with:)`, `set(email:/phoneNumber:/externalId:/profile:/profileAttribute:/pushToken:)`,
`create(event:)`, `create(subscription:)`, `resetProfile()`, `handle(notificationResponse:…)`,
`registerDeepLinkHandler`, `handleUniversalTrackingLink`, `setBadgeCount`, `setLoggingEnabled`;
Forms: `registerForInAppForms(configuration:)`, `unregisterFromInAppForms()`,
`registerFormLifecycleHandler`; Location: `registerForGeofencing()` etc.; Extension:
`KlaviyoExtensionSDK.handleNotificationServiceDidReceivedRequest`. Info.plist flags:
`klaviyo_automatic_push_open_tracking`, `klaviyo_automatic_push_token_forwarding`,
`klaviyo_badge_autoclearing`, `klaviyo_app_group`.

Everything in sections 2–8 is internal and can change without touching this surface. Additive
configuration (e.g. an optional `KlaviyoConfig` parameter on `initialize`, or a `flush()` method)
is contract-compatible.
