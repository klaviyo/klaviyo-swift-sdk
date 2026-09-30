# 02 — Research: what the Klaviyo Client API already lets the SDK do
Type: research
Status: resolved
Blocked by: —

## Question

What does `POST /client/event-bulk-create` require and guarantee (one profile per request? max events?
per-event `unique_id`/`time`/`value`? error `source.pointer` granularity on partial invalidity? rate
limits? supporting `revision`s)? Do any Client API endpoints document gzip request bodies? Do
`/client/push-tokens` payloads accept profile attributes (so token + profile can be one call)? Is any
forms/onsite configuration endpoint publicly documented? Output: `research/klaviyo-client-api.md`,
quotes + URLs, `UNVERIFIED` where docs are silent. Every batching/network ticket depends on this.

## Answer

Full findings with quotes and URLs: [`research/klaviyo-client-api.md`](../research/klaviyo-client-api.md).
Facts the blocked tickets need:

- **Bulk endpoint exists and is GA**: `POST /client/event-bulk-create` (changelog revision 2023-07-15).
  `data.type = "event-bulk-create"`, **one** `attributes.profile` per request (verified by the OpenAPI
  schema: events carry no per-event profile) plus `attributes.events.data[]` of `{metric, properties,
  time, value, value_currency, unique_id}`. Max 1000 events; payload ≤ 5 MB; strings ≤ 100 KB.
  ⇒ batching must be **per identity snapshot**: an identity change closes the batch (ticket 04).
- **Profile block accepts `anonymous_id`, `_kx`, `properties`, `location`, `meta.patch_properties`;
  it does NOT accept `push_token`** — so the per-event `push_token` the SDK sends today on
  `/client/events` has no home in a bulk request (04 must decide whether that field matters).
- **Rate limits differ sharply**: bulk `10/s burst, 150/m steady` vs single `/client/events`
  `350/s, 3500/m`. Whether Client limits are per-site or per-device is UNVERIFIED — if per-site, a
  large fleet flushing batches could 429 where single events did not; 04/08 must plan for
  `Retry-After` on the bulk path and possibly a fallback to single sends.
- **Failure semantics**: a duplicate `unique_id` inside a batch fails the whole request ("no events
  will be processed"); the default `unique_id` is time-to-the-second, so the SDK's UUID per event must
  be kept. Index-level `source.pointer` for a bad event, and partial acceptance, are UNVERIFIED —
  08 must design for all-or-nothing rejection (drop-and-split strategy) until the backend confirms.
- **Token + profile can be one call**: `/client/push-tokens` `profile` accepts `properties`,
  `location`, `patch_properties` (but lacks `anonymous_id`). No bulk endpoint for profiles, tokens,
  or subscriptions.
- **gzip request bodies**: UNVERIFIED — no mention anywhere in docs/OpenAPI (only a "5 MB
  (decompressed)" hint). Ticket 09 needs a backend confirmation before investing.
- **429**: `Retry-After` (int seconds) replaces `RateLimit-*` headers; matches the SDK's current
  handling.
- **No public forms/onsite definitions endpoint**; `klaviyo.js?env=in-app` and
  `/onsite/track-analytics` are undocumented. Ticket 11's option C (native trigger evaluation) needs
  a new or newly-documented contract from the forms team.
- Doc inconsistency to flag to the API team: max event properties 400 (reference) vs 300 (rate-limits doc).
