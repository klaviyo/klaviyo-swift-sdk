# In-App Forms

Display Klaviyo in-app forms, configure sessions, personalize forms, and observe form events.

## Overview

> Note: In-app forms are available in SDK version
> [4.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/4.2.0) and later.

[In-app forms](https://help.klaviyo.com/hc/en-us/articles/34567685177883) are messages shown to
mobile app users while they're actively using an app. You create in-app forms in a drag-and-drop
editor in the Sign-Up Forms tab in Klaviyo. Follow the steps in this article to integrate forms with
your app. The SDK displays forms according to their targeting and behavior settings, and collects
delivery and engagement analytics automatically.

In-app forms support advanced targeting and segmentation. In your Klaviyo account, you can configure
forms to target or exclude specific segments of profiles, and configure event-based triggers and
delays. The table below shows the features available in each SDK version.

### Prerequisites

- `KlaviyoSwift` and `KlaviyoForms` added to your app target and imported. See
  [Getting Started](/documentation/klaviyoswift/gettingstarted).
- We strongly recommend using the latest version of the SDK, to stay compatible with the latest
  in-app forms features. The minimum SDK version that supports in-app forms is 4.2.0. Forms that use
  unsupported features don't appear in your app until you update to a version that supports them.
- If you're upgrading from 4.2.0–4.2.1, read the
  [Migration Guide](/documentation/klaviyoswift/migrationguide#Migrating-to-v500) to understand
  the changes to in-app forms behavior.

| Feature | Minimum SDK version |
|--------------------|---------------------|
| Basic in-app forms | 4.2.0 |
| Time delay | 5.0.0 |
| Audience targeting | 5.0.0 |
| Event triggers | 5.1.0 |

## Set up in-app forms

To let your app display in-app forms, call
``KlaviyoCore/KlaviyoSDKModule/registerForInAppForms(configuration:)`` after initializing the SDK
with your public API key. Once you've registered, the SDK may show an overlay view at any time to
present a form, according to the targeting and behavior settings in your Klaviyo account.

For the best user experience, register after any splash screen or loading animation has finished.
Depending on your app's architecture, this might be in your app delegate's
`application(_:didFinishLaunchingWithOptions:)` method.

```swift
import KlaviyoSwift
import KlaviyoForms

// if registering in the same location where you're initializing the SDK
KlaviyoSDK()
    .initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
    .registerForInAppForms()

// if registering elsewhere after `KlaviyoSDK` is initialized
KlaviyoSDK().registerForInAppForms()
```

In-app forms respond automatically when the API key or the profile data changes. You don't need to
register again.

### Configure the session timeout

A "session" is a logical unit of user engagement with the app: a series of foreground interactions
within a continuous or near-continuous time window. Sessions matter for in-app forms because a user
shouldn't see a form more than once in a single session.

A session times out after a period of inactivity. When a user launches the app, if the time since
their previous interaction exceeds the timeout, the SDK starts a new session.

The timeout defaults to 3600 seconds (1 hour). To change it, pass an ``InAppFormsConfig`` to
``KlaviyoCore/KlaviyoSDKModule/registerForInAppForms(configuration:)``. For example, to set a
30-minute session timeout:

```swift
import KlaviyoForms

// e.g. to configure a session timeout of 30 minutes
let config = InAppFormsConfig(sessionTimeoutDuration: 1800)
KlaviyoSDK().registerForInAppForms(configuration: config)
```

## Unregister from in-app forms

If you need to stop the SDK from displaying in-app forms, for example when the user logs out, call
``KlaviyoCore/KlaviyoSDKModule/unregisterFromInAppForms()``:

```swift
import KlaviyoForms

KlaviyoSDK().unregisterFromInAppForms()
```

After you unregister, the SDK treats the next call to `registerForInAppForms()` as a new session.

## Personalized forms authentication

> Note: Personalization is in limited availability for select Klaviyo customers. Contact your CSM
> to be enrolled.
>
> Personalization is available in SDK version 5.5.0 and later.

Personalized in-app forms show content from the signed-in user's Klaviyo profile. Your app proves
who the user is with a JSON Web Token (JWT).

Set up an authenticated endpoint on your backend that mints a fresh JWT for the signed-in user.
Keep the signing credentials on your server. The JWT must carry valid `iat` and `exp` claims and the
user's matching `email` claim. Keep the SDK's profile identifiers in sync with the signed-in user
(see [Profiles and Events](/documentation/klaviyoswift/profilesandevents)).

After initializing the SDK, register a provider that fetches a token from your backend with
`registerAuthTokenProvider(_:)`:

```swift
KlaviyoSDK().registerAuthTokenProvider {
    // Replace with your own call. Apply a timeout to the request.
    try await authService.fetchKlaviyoJWT()
}
```

Register the provider once and keep it registered across profile changes.

On logout, clear the SDK profile:

```swift
KlaviyoSDK().resetProfile()
```

A form that's already open keeps its token until it expires, whether you call `resetProfile()` or
`unregisterAuthTokenProvider()`. `unregisterAuthTokenProvider()` turns personalization off; it
isn't a logout.

### Provider requirements

The SDK doesn't time out your provider, so your code must:

- **Return or throw exactly once.** Return the JWT or throw an error for each call to the provider.
  The SDK calls the provider whenever it needs a fresh token, on a background task.
- **Report errors by throwing.** The SDK catches errors thrown from the provider, so throw instead of
  returning an empty or placeholder token.
- **Bound your own work.** Apply a timeout to every network call. A provider that never returns
  blocks later token fetches until you register, unregister or reset the profile.
- **Fail fast.** If you can't produce a token, for example when no user is signed in, throw instead
  of waiting or retrying.
- **Pass on the original network error.** The SDK retries after reconnecting when the provider
  throws a `URLError`, so rethrow the original `URLError` without wrapping it.

## Monitor form lifecycle events

> Note: Form lifecycle events are available in SDK version 5.3.0 and later.

You can register a handler with
``KlaviyoCore/KlaviyoSDKModule/registerFormLifecycleHandler(_:)`` to track when forms are shown or
dismissed, or when users tap call-to-action buttons. This is useful for sending form engagement data
to third-party analytics platforms such as Amplitude, Segment or Mixpanel. The handler receives a
``FormLifecycleEvent``:

```swift
import KlaviyoForms

KlaviyoSDK().registerFormLifecycleHandler { event in
    switch event {
    case .formShown(let formId, let formName):
        // Track when a form is displayed
        Analytics.track("Klaviyo Form Shown", properties: [
            "formId": formId,
            "formName": formName
        ])
    case .formDismissed(let formId, let formName):
        // Track when a form is dismissed
        Analytics.track("Klaviyo Form Dismissed", properties: [
            "formId": formId,
            "formName": formName
        ])
    case .formCtaClicked(let formId, let formName, let buttonLabel, let deepLinkUrl):
        // Track when a user taps a call-to-action button
        Analytics.track("Klaviyo Form CTA Clicked", properties: [
            "formId": formId,
            "formName": formName,
            "buttonLabel": buttonLabel,
            "deepLinkUrl": deepLinkUrl.absoluteString
        ])
    }
}
```

The handler is called on the main thread and receives events for all form interactions. To remove
it, call ``KlaviyoCore/KlaviyoSDKModule/unregisterFormLifecycleHandler()``:

```swift
KlaviyoSDK().unregisterFormLifecycleHandler()
```

The handler is optional and doesn't affect how forms work. Forms continue to display and track
analytics in Klaviyo whether or not a handler is registered.

Links in forms are delivered to the deep link handler you register in `KlaviyoSwift`. See
[Deep Linking](/documentation/klaviyoswift/deeplinking).
