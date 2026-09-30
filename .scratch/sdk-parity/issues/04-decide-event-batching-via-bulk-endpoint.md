# 04 — Decide: batch events through `/client/event-bulk-create`
Type: grilling
Status: open
Blocked by: 01, 02

## Question

Given the bulk endpoint's constraints (per 02), how does the SDK batch? Decide: batch boundary rules
(one profile snapshot per batch — identity change closes a batch; push-token/profile/subscription
requests stay single); max events per batch (API allows 1000; competitors' defaults from 01);
whether `$opened_push` / geofence events still bypass batching for immediacy; whether `unique_id`
per event is preserved for server-side dedup across retries; how a 4xx on a batch is handled (drop the
pointed-at event and resend the rest, vs drop the batch); how the persisted queue represents
"events" vs "requests" (today the queue stores pre-built requests — batching implies storing events
and building requests at flush time, which touches 06). Output: the batching ADR, with expected
request-count reduction and any public-API impact (none expected).
