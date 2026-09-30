# 07 — Decide: move the SDK pipeline off the main thread
Type: grilling
Status: open
Blocked by: 03, 06

## Question

Every public call hops to main and the reducer (payload construction, `AnyCodable` wrapping,
eviction scan, state diffing for three subscribers) runs there. If 03's numbers show meaningful
main-thread time under realistic bursts, decide: (a) run the store on a dedicated serial
`DispatchQueue`/actor and hop to main only for UIKit reads (`UIDevice`, `UIApplication`
state) and host callbacks; (b) keep the store on main but make it cheap (persist-on-flush from 06
removes the O(queue) diffing; typed payloads replace `AnyCodable` at enqueue); (c) both. Also decide
ordering guarantees (host calls `set(email:)` then `create(event:)` — the event must carry the
email), and how `KlaviyoSDK.email/phoneNumber/externalId` getters behave (they read store state
synchronously today). Output: threading ADR and the invariants tests must pin.
