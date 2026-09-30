# 13 — Decide: Swift 6 / strict concurrency and minimum iOS
Type: grilling
Status: open
Blocked by: 01, 07

## Question

Competitors' posture on Swift 6 language mode, strict concurrency, and min-iOS (from 01) vs ours
(Swift 5.9 tools, iOS 13, global mutable `environment`, mixed Combine/GCD/Task). Decide: adopt
`-strict-concurrency=complete` as a warning gate now and Swift 6 mode when? raise min iOS to 14 or 15
(drops `#available(iOS 14)` branches, unlocks `NWPathMonitor` niceties, `Logger`), and does that
count as a breaking change for the "don't change contracts" constraint (it is a platform floor, not
an API change — confirm with the team)? What to do with `public var environment`. Output: toolchain
ADR with a sequenced plan.
