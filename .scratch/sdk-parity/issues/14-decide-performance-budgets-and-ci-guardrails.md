# 14 — Decide: performance budgets and the CI that enforces them
Type: grilling
Status: open
Blocked by: 03

## Question

Using 03's baseline, set budgets the SDK commits to and publishes (competitors publish size/perf
claims per 01): compressed size per module, main-thread ms per `create(event:)`, init-to-ready time,
bytes per 100 events, IAF idle memory. Decide which get a CI check (`XCTMetric` performance tests on
a simulator? binary-size diff on PRs? memory test on a device farm?), the regression tolerance, and
where the numbers are published (README table). Output: budgets ADR.
