# 10 — Decide: In-App Forms bootstrap reliability
Type: grilling
Status: open
Blocked by: —

## Question

One 10 s handshake timeout after `registerForInAppForms()` calls `destroyWebviewAndListeners()`, which
clears `isInitializingOrInitialized` and drops lifecycle observation — forms stay disabled for the
process until the host re-registers. Decide the recovery policy: retry with backoff while the app is
foregrounded; re-attempt on network regain (needs the reachability signal from KlaviyoCore); retry on
next foreground; cap on attempts; whether the timeout itself should scale with network quality; and
what the host is told (lifecycle handler event? log only?). Small, unblocked, high-value — a good
first frontier ticket. Output: bootstrap-reliability ADR (the fix itself is a quick win listed on the
map).
