# 06 — Decide: how the outbound queue is stored
Type: grilling
Status: open
Blocked by: 01, 04

## Question

Today the entire `KlaviyoState` (identity + push data + the whole queue with full payloads) is
`Equatable`-diffed on every store emission, debounced 1 s, and rewritten as one JSON file; events in
the last second before a kill are lost; cost per change is O(queue). Options: (a) keep the single
file but persist only on flush/background/terminate and store identity separately; (b) append-only
event log (one small file per event or a JSON-lines file) with compaction at flush; (c) SQLite via
`sqlite3` (no new dependency; what Braze/OneSignal use per 01). Decide the store, the write cadence
(per event vs per batch), crash-safety guarantee (which events may be lost), the memory bound (queue
cap stays 200? rises with batching?), eviction rule, and the **migration** of existing
`klaviyo-<key>-state.json` files (must drain legacy queued requests, keep anonymousId/token). Output:
persistence ADR.
