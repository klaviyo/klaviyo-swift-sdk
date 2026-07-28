# Handoff: grounding the Klaviyo ↔ Shopify mobile recommendations in app-side code

**Mission:** Write the app-side (integrator) code that a Shopify-powered mobile app would actually use to identify a shopper, and use those call sites to confirm or kill four specific claims about how the Klaviyo SDKs behave — above all the `setProfile` reset hazard.

This file is a read-once bridge document. An identical copy exists in both repos, since the work spans them:
`klaviyo-swift-sdk/.scratch/handoffs/shopify-mobile-identity.md` and `klaviyo-android-sdk/.scratch/handoffs/shopify-mobile-identity.md`.

## Origin

- Slack thread, `#C07PEFEQ518`, from Mark Piana: https://klaviyo.slack.com/archives/C07PEFEQ518/p1785258531416849
- The reply this handoff continues: https://klaviyo.slack.com/archives/C07PEFEQ518/p1785268664370739?thread_ts=1785258531.416849&cid=C07PEFEQ518
- The recommendations doc under review — "Klaviyo Mobile SDK ↔ Shopify Integration Recommendations", 11 numbered items: https://docs.google.com/document/d/1HffO5C6YCOIeoPeFaiZGnQqcVTytJQ__lAud1oDqt6g/edit
- Shopify's mobile surface (Checkout Kit, Storefront API, Accelerated Checkouts): https://shopify.dev/docs/storefronts/mobile

Item numbers `#1`–`#11` throughout this file refer to that Google Doc's numbering. Both repos are on branch `claude/slack-message-review-kx20h8`.

## Established

Each claim below was verified against the checked-out source at the anchor given.

1. **Identity stitching already works, via `anonymous_id` in the same payload.** Every profile call sends `anonymous_id` alongside email / phone / external_id in one request body.
   - Swift: `Sources/KlaviyoSwift/StateManagement/KlaviyoState.swift:267-273`
   - Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/networking/requests/ProfileApiRequest.kt:24-59`, `ANONYMOUS_ID` at `:38`

   Consequence: the doc's premise — that split profiles arise because identifier *format* mismatches defeat "auto-merge-on-identifier-match" — is not the mechanism in play. Neither SDK merges anything client-side; the anonymous ID rides along and the backend resolves it. The realistic failure mode in a Shopify app is that the app never calls an identify method at all, because identity lives inside Checkout Kit or the Customer Account API.

2. **`setProfile` resets state and regenerates the anonymous ID whenever the incoming identifier *set* differs from what is stored.**
   - Swift: `Sources/KlaviyoSwift/StateManagement/StateManagement.swift:544-561` — the reset is at `:559-561`, and it is `state.reset(preserveTokenData: false)`, so push token data is dropped as well.
   - Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/state/KlaviyoState.kt:110-125` — reset at `:123-125`

   The comparison is positional over `[email, phoneNumber, externalId]`. A *narrower* incoming set — email only, on a profile already carrying an external_id — therefore counts as "different" and triggers the reset. This is the hazard behind doc items #3 and #4.

3. **The per-identifier setters are additive and do not reset.**
   - Swift: `Sources/KlaviyoSwift/StateManagement/KlaviyoState.swift:140-155` (`updateStateWithProfile` sets each identifier independently); reducer path at `Sources/KlaviyoSwift/StateManagement/StateManagement.swift:247`
   - Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/state/KlaviyoState.kt:137-140` (`setAttribute`); public surface documented at `sdk/analytics/src/main/java/com/klaviyo/analytics/Klaviyo.kt:148-222`

   So `setEmail` / `setPhoneNumber` / `setExternalId` are the safe primitives for incremental identity arriving from a Shopify callback.

4. **Whitespace is already trimmed on both platforms. Nothing lowercases email or formats phone to E.164.**
   - Swift: `Sources/KlaviyoSwift/StateManagement/KlaviyoState.swift:479-488` — trims, and emits a developer warning via `logDevWarning` when an identifier is empty or unchanged
   - Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/state/PersistentObservableString.kt:17-23`, plus `state/KlaviyoState.kt:112-116`; documented at `Klaviyo.kt:148`, `:164`, `:192`, `:222`

5. **`Viewed Product` and `Opened App` already exist as metrics, and neither is auto-fired by the SDK.**
   - Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/model/EventMetric.kt:12-13`
   - Swift: `Sources/KlaviyoSwift/Models/Event.swift:14`, `:106`
   - Grepping `OPENED_APP` under `sdk/*/src/main` returns only the enum definition — every call site is app-side, e.g. `sample/src/main/java/com/klaviyo/sample/SampleActivity.kt:38` and `SampleViewModel.kt:139-140`.

6. **No consent framework exists in either SDK** (doc #11). The only `consent` references are form-submission fields in the forms bridge tests. This would be net-new infrastructure, not parity.

7. **Klaviyo normalizes phone numbers server-side on ingest** by stripping symbols, spaces, and letters; the API accepts E.164 only. Source is Klaviyo's SMS phone-formatting help article, i.e. secondary rather than the API reference. Treat the symbol-stripping as established and the missing-country-code behavior as open (below).

8. **The Swift package has exactly one runtime third-party dependency.** `Package.swift:28-35` — `AnyCodable`; the pointfree packages are used by test targets only. Any libphonenumber-style addition would be the first of its kind.

## Open questions

- **Does the backend match emails case-insensitively?** Not verified, and it is the crux. Mark's own comment on doc #1 reads: *"I don't think we actually need to do this, but we should confirm."* Cheapest settle: ask whoever owns profiles/identity, or `POST` the same address in two casings to `client/profiles` on a test account and count the resulting profiles. **This one answer collapses or validates half of #1.**
- **What does `client/profiles` do with a phone number that has no country code?** Reject, silently drop, or best-effort parse against the account's default country? This decides whether client-side E.164 has any value at all. Same cheap test.
- **Where should Shopify's customer GID live?** Putting it in `external_id` collides with merchants already populating external_id from another system. This is a data-model decision, not an SDK one.
- **Doc #5 — can we get the `read_customer_email` / `read_customer_phone` Shopify scopes?** Owned by Integrations/Partnerships. Without them, guest-checkout identity is unreachable from the app side, which gates whether *any* checkout-based identity work is worth building. Highest-value item on the doc, and not an SDK task.

## Decisions and non-goals

Settled in the Slack thread. Do not relitigate without new evidence.

- **No client-side E.164 formatting.** The country code is not reliably inferable — device locale and SIM region are bad proxies (travel, dual-SIM, eSIM). A wrong guess converts a recoverable server-side rejection into a *silently wrong* identifier that can merge a shopper into someone else's profile: worse than the bug it fixes.
- **No libphonenumber.** Meaningful binary size on Android, no good Swift equivalent, and it would be the Swift package's first runtime dependency beyond AnyCodable.
- **No Apollo dependency and no GraphQL-interceptor auto-instrumentation inside the SDK** (doc #3, #9). Shopify prescribes no GraphQL client; merchants use Apollo, Shopify's generated clients, or plain URLSession/OkHttp. Acceptable as sample-app code only.
- **No JWT parsing in the SDK** (doc #2). We would own a parser tracking Shopify's token schema, and cannot verify signatures without their JWKS. A documented snippet gets most of the value at none of the maintenance cost.
- **No auto-firing a new session event at `initialize()`** (doc #10). It changes event volume for every existing integrator, which is billing-relevant. `Opened App` already exists for apps that want it, and firing web's "Active on Site" from a native app risks polluting web-specific segments.
- **Doc #8 is not new API surface.** The `Viewed Product` metric already exists; the real gap is property-schema parity with web onsite tracking, so the same flows and segments fire. That is a mapper plus documentation.

## Constraints

- Android public API must stay cleanly Java-callable (`@JvmStatic` / `@JvmOverloads`, plus a `*JavaApiTest.java`) — see `klaviyo-android-sdk/CLAUDE.md`.
- Swift: 110-char lines, `swiftlint --fix --strict`, `swiftformat .`. Android: `./gradlew ktlintCheck`, no wildcard imports, avoid `!!` and `lateinit`.
- Android tests require **Java 17** — Java 21 breaks the reflection-based static field overrides.
- State-touching changes: TCA `TestStore` on Swift, Mockk + `BaseTest` on Android.
- Neither repo tracks `.claude/` (gitignored in both), so skills added there are local-only. `.scratch/` is **not** ignored — this file will show up in `git status`.

## Where the relevant code lives

App-side — the surface this mission is about:
- Swift: `Examples/KlaviyoSwiftExamples/SPMExample/`, `Examples/KlaviyoSwiftExamples/CocoapodsExample/`
- Android: `sample/src/main/java/com/klaviyo/sample/` (`SampleActivity.kt`, `SampleViewModel.kt`, `SampleView.kt`)

SDK-side:
- Swift: `Sources/KlaviyoSwift/StateManagement/{StateManagement.swift,KlaviyoState.swift}`, `Sources/KlaviyoSwift/Klaviyo.swift`
- Android: `sdk/analytics/src/main/java/com/klaviyo/analytics/{Klaviyo.kt,state/KlaviyoState.kt,networking/requests/ProfileApiRequest.kt}`

## First concrete step

Reproduce the reset hazard from app-side code. It is the one claim that is both load-bearing and cheaply falsifiable, and the answer reorders the whole doc.

In the sample app (`klaviyo-android-sdk/sample/` is the faster of the two to run), write the call sequence a Shopify-powered app actually produces:

1. `Klaviyo.setExternalId("<shopify-customer-gid>")` — shopper signs in via the Customer Account API
2. `Klaviyo.setProfile(Profile(email = "shopper@example.com"))` — checkout completes and the delegate callback yields email only

Then observe, from the outgoing request payloads and the persisted anonymous ID:

- whether the anonymous ID regenerates between steps 1 and 2
- whether `external_id` survives step 2
- on Swift, whether push token data is dropped, given `reset(preserveTokenData: false)` at `StateManagement.swift:559-561`

Then run the same sequence with `Klaviyo.setEmail(...)` substituted for step 2, and confirm it is additive.

If the hazard reproduces, that is the finding: doc items #3 and #4 are net-negative as written, and the real deliverable becomes a Shopify integration guide plus a sample that shows the additive setters at the right call sites — not new SDK surface.
