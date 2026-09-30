# 01 — Research: how Customer.io, Braze and OneSignal engineer their iOS SDKs
Type: research
Status: claimed (research agent running this session)
Blocked by: —

## Question

From primary sources (public source code, official docs), what do the three competitor iOS SDKs do for:
event queue persistence and batching; flush triggers and intervals; retry/backoff and offline
handling; request compression and URLSession configuration; init latency and threading model;
memory/binary-size claims and modularization; in-app message architecture (where triggers are
evaluated, how definitions and assets are cached, when the WKWebView is created, display rules);
session semantics; developer-facing config knobs; Swift 6 / privacy-manifest / min-iOS posture?
Output: `research/competitor-sdks.md` with a per-dimension comparison table and a "patterns all three
share" list (the table-stakes signals every later ticket argues against).
