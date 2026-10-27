# Tests

XCTest targets, one per module, declared as `.testTarget` in `../Package.swift`:

- `KlaviyoCoreTests/`: networking, auth (`Auth/`), event buffer/bus, identity store, encoding.
- `KlaviyoSwiftTests/`: `KlaviyoSDK` API, state management reducer, push/swizzling, deep links.
- `KlaviyoFormsTests/`: in-app forms presentation manager, web view model, native bridge events.
  Loads `Assets/IAFUnitTest.html` as a test resource; shared mocks are in `Mocks/`.
- `KlaviyoLocationTests/`: geofence model, cooldown tracker, distance calculator, location manager.
- `KlaviyoSwiftExtensionTests/`: action button parsing and the extension/core allowlist parity test.

## Running

There is no `swift test` workflow. Tests run through `xcodebuild` on an iOS Simulator:

```bash
make test-library                     # debug config
make CONFIG=release test-library      # release config (ENABLE_TESTABILITY=YES)
make IOS_RUNTIME="iOS 26" test-library  # pick a different simulator runtime family
```

`make test-library` passes `KLAVIYO_TESTING` as a compilation condition. Test hooks in `Sources/` are
guarded by `#if DEBUG || KLAVIYO_TESTING`. CI (`.github/workflows/swift.yml`) runs debug and release
across Xcode 15.4, 16.4 and 26.5.

## Conventions

- One `*Tests.swift` file per implementation class. Larger areas split by concern
  (e.g. `IAFPresentationManager*Tests.swift`, `Auth/AuthTokenManager*Tests.swift`).
- Put shared setup in the per-target helpers (`TestUtils.swift`, `KlaviyoTestUtils.swift`,
  `KlaviyoFormsTestUtils.swift`, `KlaviyoLocationTestUtils.swift`, `*TestHelpers.swift`, `*TestSupport.swift`)
  instead of duplicating it.
- Reducer/effect tests use the vendored `TestStore` in `KlaviyoSwiftTests/Vendor/ComposableArchitecture/`
  (vendored, excluded from lint/format).
- Snapshot tests use `swift-snapshot-testing`. Reference files live in `__Snapshots__/` next to the
  test file. If you change an encoded payload, re-record the snapshots and review the diff.
  `__Snapshots__` is excluded from pre-commit, SwiftLint and SwiftFormat.
- `bump-version.sh` rewrites hard-coded SDK versions in `KlaviyoCoreTests/NetworkSessionTests.swift`
  and in snapshot files. Don't hand-edit those version strings.
