# Personalization pin drift report (MAGE-1415)

Date: 2026-10-15
Baseline: `origin/master` @ `0551e22b` (personalization has landed on master via #763,
docs #760, examples #768, rel/5.5.0 merged by #773 — master is now the authoritative
reference, so this report diffs the retrofit stack **against master**, not the pin).
Branch: `isobellelim/mage-1415-personalization-retrofit-66-parity-gate-pin-re-sync-full` @ `dcae7adf`
Pin: `db58bbee45258de84cb4b0d5bc6fcd1a7d9a826d` (ancestor of master; its source branch
`feat/jwts-for-personalized-forms` is gone from origin).

**REPORT-ONLY. No drift was ported and no ported file was edited.**

## Headline

Drift is small and concentrated. Of all paths this stack ported, the retrofit branch
differs from master in only **2 production files with substantive behavior changes**
(`AuthTokenManager.swift`, `IAFWebViewModel.swift` plus its presentation manager),
**1 cosmetic production file** (`FormLifecycleEvent.swift` doc comment), and a set of
test/helper files. Everything else this stack ported is byte-identical to master.

Substantive behavior changes on master not present on this branch:

1. **JWT refresh-sleep overflow fix (#765, `2e915104`)** — `AuthTokenManager` caps each
   refresh-loop sleep at 24h (`maxRefreshSleepSeconds`) instead of sleeping the full
   remaining duration in one shot; the pin-era code can overflow `UInt64` nanoseconds
   for far-future expiries. This branch still has the pin-era unbounded sleep.
2. **Provider-error log privacy (`86136934`)** — master logs the provider error with
   private privacy (`"Auth token provider error: \(reason)"`); this branch has the
   pin-era `privacy: .public` message.
3. **Forms deep-link hardening (#705 chain)** — master removed the `canOpenURL` gate on
   in-app form deep links (`42895e75`), updated the `FormLifecycleEvent.formCtaClicked`
   doc comment, and switched the WebView console-debug flag from
   `localStorage.debug_filter` to `localStorage.debug`.
4. **Outbound JS bridge `trackProfileEvent` v2 (#705 chain)** — `IAFNativeBridgeEvent`
   advertises `trackProfileEvent` at version 2 and maps the envelope to event fields
   carrying `value_currency` (`78a8c587`, `39e2c8b2`, depends on core `da69173f`).
5. **Release-config testability hook (#765)** — `IAFPresentationManager`'s test
   initializer is gated `#if DEBUG || KLAVIYO_TESTING` on master vs `#if DEBUG` here.

## File classification (branch vs `origin/master`, restricted to ported paths)

### Identical to master (no drift)

- `Sources/KlaviyoCore/Auth/` — all files except `AuthTokenManager.swift`
  (`AuthTokenError`, `AuthTokenProvider`, `IdentityGenerationTracker`,
  `IdentityTransition`, `JWTParser`, `JWTValidationFailure`, `ValidatedToken`)
- `Sources/KlaviyoCore/Models/ProfileData+Identified.swift`
- `Sources/KlaviyoCore/Utils/OnceResolver.swift`
- `Sources/KlaviyoCore/Utils/URLError+Ext.swift`
- `Sources/KlaviyoSwift/Klaviyo+AuthToken.swift` (byte-identical)
- `Tests/KlaviyoSwiftTests/AuthTokenFacadeOrderingTests.swift`

### Differs from master — verbatim-here (master's version would apply cleanly;
branch file is byte-identical to the pin)

- `Sources/KlaviyoCore/Auth/AuthTokenManager.swift` (drift items 1–2 above)
- `Sources/KlaviyoForms/InAppForms/IAFPresentationManager.swift` (item 5 + deep-link)
- `Sources/KlaviyoForms/InAppForms/IAFWebViewModel.swift` (items 3–4)
- `Sources/KlaviyoForms/InAppForms/Models/FormLifecycleEvent.swift` (doc comment)
- `Sources/KlaviyoForms/InAppForms/Models/IAFNativeBridgeEvent.swift` (item 4)
- `Sources/KlaviyoForms/KlaviyoWebView/KlaviyoWebViewController.swift` (item 3)
- `Tests/KlaviyoFormsTests/IAFNativeBridgeEventTests.swift`
- `Tests/KlaviyoFormsTests/IAFWebViewModelPreloadingTests.swift`
- `Tests/KlaviyoCoreTests/Auth/AuthTokenManagerRefreshTests.swift` — exists only on
  master (50 lines; the #765 regression tests for the sleep cap). Not ported here.

### Differs from master — adapted-here (same file exists on both sides; this stack
re-based it onto the post-modularization architecture, so a cherry-pick would not
apply cleanly)

- `Sources/KlaviyoCore/Utils/Logger+Ext.swift` — this branch uses `UnfairLock`
  (modularization-era util, not on master) for `KlaviyoLogConfig`; master uses `NSLock`.
- `Tests/KlaviyoCoreTests/Auth/AuthTestHelpers.swift` — master adds
  `SleepGate.durations` recording (#765); branch is the pin version plus a small
  modularization adaptation.
- `Tests/KlaviyoFormsTests/CompanySwitchAuthTokenTests.swift`,
  `IdentityTransitionOrderingTests.swift` — rewritten by this stack to drive
  `KlaviyoCommands` + canonical Core stores instead of the TCA reducer /
  `SharedStoreMirror` that master still uses.
- `Tests/KlaviyoFormsTests/KlaviyoFormsTestUtils.swift`,
  `KlaviyoWebViewControllerTests.swift` — modularization-era test-environment
  differences (no `ArchiverClient`, no `timer`, plain `TestJSONDecoder`).
- `Tests/KlaviyoFormsTests/IAFWebViewModelTests.swift` — branch is pin + Task 4
  adaptations; master grew ~344 lines of deep-link / `trackProfileEvent` tests.
- `Tests/KlaviyoFormsTests/IAFPresentationManagerOutboundEventTests.swift` — exists
  only on master (98 lines; outbound-bridge regression tests from #705). Not ported.
- `KlaviyoForms.podspec` — master is at 5.5.0 (version bump `80cc375d`); this branch
  intentionally carries the modularization stack's own versioning. Not drift to port.

## Work list, if the drift is ever ported onto this stack

In dependency order: (a) `AuthTokenManager` sleep cap + private logging + the
`AuthTokenManagerRefreshTests` additions and `SleepGate.durations` helper;
(b) `IAFPresentationManager` `KLAVIYO_TESTING` gate (check interplay with this stack's
own release-test configuration); (c) the #705 forms chain (deep-link gate removal,
`trackProfileEvent` v2, console debug flag, outbound-event tests) — note (c) is
feature work independent of personalization and may belong on the modularization
feature branch regardless.

## Appendix: pin..master log for ported paths

54 commits total on `pin..origin/master`; 28 touch the ported paths. Subjects:

```
86136934 Update Sources/KlaviyoCore/Auth/AuthTokenManager.swift
88f07332 feat: demonstrate JWT providers in Swift example apps (#768)
2e915104 Fix JWT refresh overflow and release test initialization (#765)
0bb71d70 Merge rel/5.5.0 into personalized forms feature
2b7c24dd test(KlaviyoForms): drop ticket reference from preload test comment
5910da1d Merge remote-tracking branch 'origin/rel/5.5.0' into asb/mage-1070-pr-cleanup
e351e554 fix(KlaviyoForms): strip internal names and CI narration, fix test dispatcher leak
a248ae83 fix: preserve deep link busy guard and generalize test fixtures
d1a4f9f6 Merge pull request #705 from klaviyo/ecm/iaf-profile-event-properties
9ace8811 Merge pull request #740 from klaviyo/asb/mage-1319-preloading-test-timeout
8f406194 test(KlaviyoForms): drop the CI run id from a test comment
c965f053 test(KlaviyoForms): drop the ticket reference from a test comment
ac831d91 test(KlaviyoForms): record why the preloading budgets are the sizes they are
bbcac860 test(KlaviyoForms): assert the canOpenURL premise in the lifecycle test
a87d8a2b test(KlaviyoForms): widen the preloading success budget and drop its dead expectation
93db677e test(KlaviyoForms): address Bugbot review on the deep link tests
d419a910 test(KlaviyoForms): run the WebKit end-to-end deep link test locally only
83179ad1 Merge branch 'rel/5.5.0' into asb/mage-1070-ios-form-deeplink
78a4a767 test(KlaviyoForms): raise deep link end-to-end timeout for cold CI runners
9cf9ae05 test(KlaviyoForms): end-to-end deep link regression through a real WKWebView
42895e75 fix(KlaviyoForms): remove canOpenURL gate from in-app form deep links
80cc375d chore(release): bump version to 5.5.0
ce758d0a test(forms): pin that the outbound bridge does not mutate its event
39e2c8b2 fix(forms): carry value_currency on the outbound JS bridge
da69173f feat(core): support value_currency on events
9244a4ef test(forms): pin non-numeric trackProfileEvent value, correct a comment
b89c5d5f docs(forms): correct the handshakeEvents comment
79ad0fbe feat(forms): advertise trackProfileEvent v2 in the handshake
78a8c587 fix(forms): map trackProfileEvent envelope to event fields
```
