# Sources

Production code for the SDK. Each subdirectory is one SwiftPM target declared in `../Package.swift`
and (except `KlaviyoAutomaticPushBootstrap`) one CocoaPods spec at the repo root.

## Modules

- `KlaviyoCore/`: shared internals used by every other module except the extension: networking
  (`Networking/`), API models (`Models/`), auth tokens and JWT handling (`Auth/`), event buffering and
  dispatch, identity store, logging, and the SDK version (`Utils/Version.swift`). Depends on `AnyCodable`.
- `KlaviyoSwift/`: the public `KlaviyoSDK` entry point (`Klaviyo.swift`): profiles, events, push
  token/open handling, badge count, deep links and tracking links. State lives in a TCA-style reducer
  under `StateManagement/`. Ships `PrivacyInfo.xcprivacy` as a resource.
- `KlaviyoAutomaticPushBootstrap/`: small Objective-C target (`.m` plus a public header in `include/`).
  Its `+load` hooks `UIApplication.setDelegate:` when the app's Info.plist opts into automatic push
  (`klaviyo_automatic_push_token_forwarding` / `klaviyo_automatic_push_open_tracking`). CocoaPods
  compiles it into the `KlaviyoSwift` pod.
- `KlaviyoForms/`: in-app forms: `IAFPresentationManager`, `IAFWebViewModel` and a `WKWebView`
  host (`KlaviyoWebView/`). HTML/JS resources live in `InAppForms/Assets` and `KlaviyoWebView/Resources`.
- `KlaviyoLocation/`: geofencing on top of `CoreLocation`; depends on `KlaviyoSwift` and `KlaviyoCore`.
- `KlaviyoSwiftExtension/`: helpers for a Notification Service Extension (rich push, badge count,
  action buttons). It has **no dependencies** and must not import `KlaviyoCore`.

## Conventions

- `KlaviyoSwiftExtension` keeps intentional copies of `ActionType`, `KlaviyoCategoryManager`, and
  `URLSchemeAllowlist` from `KlaviyoCore`, because extensions cannot depend on `KlaviyoCore`. If you change one copy, change
  the other; `Tests/KlaviyoSwiftExtensionTests/URLSchemeAllowlistParityTests.swift` guards the allowlist.
- Cross-module internals use Swift `package` access. CocoaPods needs the matching `-package-name` flags
  in each podspec's `pod_target_xcconfig`. Update them if you add a module dependency.
- Test-only hooks are wrapped in `#if DEBUG || KLAVIYO_TESTING`. `make test-library` sets
  `KLAVIYO_TESTING` so the hooks also exist in release-config test runs.
- When you add resources to a target, register them in both `Package.swift` (`resources:`) and the
  podspec (`resource_bundles`).
- Each module has its own `Logger+Ext.swift`. Add log categories there rather than creating new loggers.

## Vendored code (do not edit casually, excluded from lint/format)

- `KlaviyoSwift/Vendor/ComposableArchitecture/`: trimmed-down copy of Point-Free's TCA (`Store`,
  `Effect`, `ReducerProtocol`, ...). The SDK does not depend on the TCA package.
- `KlaviyoCore/Vendor/ReachabilitySwift.swift`: vendored Reachability.
