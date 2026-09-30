# Map: Swift SDK parity with Customer.io / Braze / OneSignal

Label: `wayfinder:map` · Tracker: local markdown (`.scratch/sdk-parity/`, see `docs` convention in the
wayfinder skill) · Child tickets: `issues/NN-*.md` · Frontier = open, unblocked, unclaimed tickets.

## Destination

An evidence-backed, prioritized set of architecture decisions (ADR-sized, one per closed ticket) for the
Klaviyo Swift SDK's **data pipeline** (queue, batching, flush, persistence, retry, network, threading)
and **In-App Forms engine**, such that the mobile team can turn them straight into implementation
tickets. Success = every decision names the chosen option, the rejected ones, the measurable target it
serves, and its public-API impact — with public-contract changes limited to *additive* configuration.

## Notes

- **Domain**: iOS SDK, Swift 5.9 toolchain, iOS 13 minimum, SPM + CocoaPods, TCA-style store on the
  main thread. Read `research/klaviyo-sdk-baseline.md` first (file-referenced description of today's
  behaviour), then `research/competitor-sdks.md` (what the three competitors do, primary sources) and
  `research/klaviyo-client-api.md` (what our Client API already supports).
- **Standing preference (from the request)**: nothing is off the table technically, but avoid changing
  existing public API contracts. Additive knobs (an optional config on `initialize`, a `flush()`) are
  acceptable; renames/removals are not.
- **Skills to consult per ticket**: `/grill-with-docs` + `/domain-modeling` for grilling tickets;
  `/prototype` for the IAF architecture spike; `/research` for research tickets.
- **Who must be in the room**: IAF engine decisions (tickets 11, 12) depend on the onsite/forms JS
  team because klaviyo.js owns targeting today — a native-SDK-only session cannot close them.
- **Measure before deciding**: tickets that claim "main-thread cost" or "WebContent memory" are gated
  on ticket 03's numbers; do not resolve them on intuition.
- **Quick wins that need no decision** (may be shipped any time, outside this map):
  - Cache `AppContextInfo` once per process; today its initializer re-parses `embedded.mobileprovision`
    with a `Scanner` on every construction (`Sources/KlaviyoCore/AppContextInfo.swift`), and it is
    constructed per event enrichment and per push-token comparison.
  - Set explicit `timeoutIntervalForRequest` on the ephemeral `URLSession` (today: 60 s default).
  - Retry the IAF handshake with backoff instead of tearing down forms for the rest of the process on
    one 10 s timeout (`IAFPresentationManager.setupFormLifecycleListener`) — ticket 10 decides the
    policy; the "don't permanently disable" part is a bug fix.

## Decisions so far

<!-- one line per closed ticket: gist, then the link that holds the detail -->

## Not yet specified

- **Session model**: forms have a 1 h inactivity session (`InAppFormsConfig`); the event pipeline has
  none. Competitors emit session start/end and key frequency caps on it. Whether Klaviyo wants a
  first-class SDK session (and what the backend would do with it) is a product question that becomes
  ticketable once 11 settles where display rules live.
- **Public configuration surface**: which of the knobs decided in 04–09 should be exposed to hosts
  (flush interval, batch size, queue cap, log level, `flush()`), and whether via an optional
  `KlaviyoConfig` on `initialize(with:)` or Info.plist. Ticketable after 04 and 05 close.
- **Wrapper SDKs** (React Native, Flutter): every pipeline change must be neutral for them; whether
  they need new bridge surface (e.g. `flush()`) depends on the config-surface decision.
- **Android parity**: the same decisions will need an Android counterpart; scope of a shared spec vs
  independent implementation is undecided.
- **SDK self-telemetry**: competitors ship SDK health signals; whether Klaviyo wants opt-in SDK
  diagnostics (queue depth, drop counts, handshake latency) and where they go is unexplored.
- **Distribution format**: prebuilt xcframeworks (faster host builds, size transparency) vs source-only.
  Depends on 14's stance on published size numbers.

## Out of scope

- Rewriting the onsite `klaviyo.js` forms engine itself (owned by the forms team). Ticket 11 decides
  *where* trigger evaluation lives and what contract the SDK needs from onsite; implementing onsite
  changes is a separate effort.
- Backend rate-limit or endpoint changes beyond what the public Client API already documents.
- Push delivery infrastructure, APNs payload design, NSE media handling (already competitive; no
  parity gap surfaced in the baseline).
- Android SDK implementation.
- Any breaking public API change (renames, removals, signature changes) — ruled out by the request.
