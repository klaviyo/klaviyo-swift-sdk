# 12 — Decide: caching and prefetch for forms assets
Type: grilling
Status: open
Blocked by: 11

## Question

Whatever 11 chooses, decide the caching layer: disk cache for `klaviyo.js`, the fonts CSS and forms
definitions (WebKit HTTP cache only today — sized/evicted by the system); a `WKURLSchemeHandler` or
`URLCache` with an explicit capacity; prefetch of form images at definition load; offline behaviour
(show cached forms? never?); cache invalidation (ETag / version in definitions); and what the
session-timeout teardown reloads vs reuses. Output: caching ADR with expected bytes-per-session and
time-to-first-form targets.
