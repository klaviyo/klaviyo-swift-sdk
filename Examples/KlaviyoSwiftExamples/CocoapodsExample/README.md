# CocoaPods example with a Klaviyo-owned spec repository

This example uses the public
[Klaviyo spec repository](https://github.com/klaviyo/klaviyo-ios-podspecs)
for the published SDK 5.5.0 podspecs. The public CocoaPods CDN still supplies
AnyCodable-FlightSchool. No SDK source is copied into the spec repository.

From this directory:

```sh
pod install --repo-update
xcodebuild build -workspace CocoapodsExample.xcworkspace \
  -scheme CocoapodsExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Inspect `SPEC REPOS` in the generated Podfile.lock: all five Klaviyo pods should
come from `https://github.com/klaviyo/klaviyo-ios-podspecs.git`; only AnyCodable
should come from trunk. KlaviyoSwift explicitly selects its source to avoid
resolving its overlapping trunk release. Duplicate-spec warnings can still occur
for the other pods while the same versions exist in both repositories.

For an existing installation, update the locked Klaviyo pods after changing the
Podfile:

```sh
pod update KlaviyoCore KlaviyoSwift KlaviyoForms KlaviyoLocation KlaviyoSwiftExtension
```

The repository is a prototype seeded with 5.5.0 only. Future releases require
manual publishing until release automation is added; the SDK's existing trunk
publishing workflow is unchanged.
