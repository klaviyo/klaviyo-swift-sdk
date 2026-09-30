# 02 — Research: what the Klaviyo Client API already lets the SDK do
Type: research
Status: claimed (research agent running this session)
Blocked by: —

## Question

What does `POST /client/event-bulk-create` require and guarantee (one profile per request? max events?
per-event `unique_id`/`time`/`value`? error `source.pointer` granularity on partial invalidity? rate
limits? supporting `revision`s)? Do any Client API endpoints document gzip request bodies? Do
`/client/push-tokens` payloads accept profile attributes (so token + profile can be one call)? Is any
forms/onsite configuration endpoint publicly documented? Output: `research/klaviyo-client-api.md`,
quotes + URLs, `UNVERIFIED` where docs are silent. Every batching/network ticket depends on this.
