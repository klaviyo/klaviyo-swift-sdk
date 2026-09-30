# 09 — Decide: network layer — reachability, compression, session config
Type: grilling
Status: open
Blocked by: 02, 05

## Question

Decide whether to: replace vendored `ReachabilitySwift` (SCNetworkReachability) with `NWPathMonitor`
(iOS 12+, no vendored code, gives `isExpensive`/`isConstrained` for free — which could replace the
Wi-Fi/cellular interval split); gzip request bodies if 02 confirms the API accepts
`Content-Encoding: gzip` (worth it only once batches exist); set `timeoutIntervalForRequest`,
`waitsForConnectivity`, `allowsExpensiveNetworkAccess`/`allowsConstrainedNetworkAccess` on the
session; whether a background `URLSession` is ever justified (probably not: small JSON POSTs);
whether to trim per-event payload weight (repeated profile block per event disappears with batching).
Output: network ADR with a table of settings and rationale.
