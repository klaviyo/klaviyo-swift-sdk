# 05 — Decide: when the queue flushes
Type: grilling
Status: open
Blocked by: 01

## Question

Today: timer-only (10 s Wi-Fi / 30 s cellular), nothing on background or terminate, in-flight work
is cancelled on background. Decide the flush trigger set: on `didEnterBackground` inside a
`UIApplication.beginBackgroundTask` window; on `willTerminate` (best effort, synchronous persist at
minimum); on network regain; on queue depth threshold; on explicit `flush()` (additive public API —
yes/no?); whether the timer stays and at what defaults given batching (04); whether cellular vs
Wi-Fi differentiation is still worth its reachability dependency; whether a `BGAppRefreshTask` is
worth registering for stragglers. Output: flush-policy ADR with the ordered trigger list, defaults,
and which knobs (if any) are host-configurable.
