# 08 — Decide: retry budget, expiry, and head-of-line blocking
Type: grilling
Status: open
Blocked by: 04

## Question

Today: a single global `retryState`; `maxRetries = 50` per request; a failing head request blocks
everything behind it; nothing expires by age. With batching (04), decide: per-request vs per-batch
retry accounting; an age-based TTL (drop events older than N days, as competitors do per 01) vs
attempt counts; whether a poison request is parked so the rest of the queue proceeds; backoff shape
(current: `max(2^n, Retry-After)` capped 300 s + 0–10 s jitter — keep?); behaviour on 401/403 and on
invalid-identifier 400s for a batch (today: reset email/phone state and drop). Output: retry ADR.
