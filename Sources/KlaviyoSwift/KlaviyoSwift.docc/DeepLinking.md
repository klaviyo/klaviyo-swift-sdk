# Deep Linking

Open the right screen in your app from push notifications, in-app forms and universal links.

## Overview

Klaviyo [deep links](https://help.klaviyo.com/hc/en-us/articles/14750403974043) take users to a
particular page in your app when they open a push notification, tap a link in an in-app form, or
tap a universal link from outside the app. The SDK supports deep linking with either URL schemes or
universal links.

## Add link-handling logic

We recommend that you put your link-handling logic in one helper method. It might parse a URL into
its components and use them to navigate to the right screen. Centralizing this logic reduces
duplicated code as you finish your setup for
<doc:DeepLinking#Handle-URL-schemes> and <doc:DeepLinking#Handle-universal-links>.

For example, you might add a method like this to your `AppDelegate` or `SceneDelegate`:

```swift
func handleDeepLink(url: URL) {
    // parse the URL into its components by creating a URLComponents object; i.e.,
    // let components = URLComponents(url: url, resolvingAgainstBaseURL: true)

    // extract the path and/or the query items from the URL components

    // use your app's navigation logic to handle routing to the appropriate
    // screen given the extracted path and/or query items
}
```

## Handle URL schemes

> Note: Your app needs SDK version 1.7.2 or later for these steps to work.

URL schemes are a simple way to enable deep linking in your app.

### Step 1: Register the URL scheme

Register your URL scheme with iOS to tell the operating system that your app can handle URLs with
that scheme. Add a `CFBundleURLTypes` entry to your app's `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>{your_bundle_identifier}</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>{your_url_scheme}</string>
        </array>
    </dict>
</array>
```

Replace `{your_url_scheme}` with the scheme you want your app to respond to, and
`{your_bundle_identifier}` with your app's bundle identifier. You can also add this entry from the
**Info** tab of your app target in Xcode. For detailed instructions, see
["Register your URL scheme"](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app#Register-your-URL-scheme)
in Apple's documentation.

`CFBundleURLTypes` is what tells iOS to route your URL scheme to your app.

### Step 2: Handle the deep links in your app

Add code to your app to process incoming URLs and navigate to the correct content. The
implementation depends on whether your app uses the SwiftUI or the UIKit life cycle.

**SwiftUI apps.** Use the
[`onOpenURL(perform:)`](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))
view modifier. Attach it to the root view in your main `App` scene:

```swift
@main
struct MyApplication: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // handle the URL
                    // if you created a helper method (see "Add link-handling logic", above), call it here
                }
        }
    }
}
```

**UIKit apps.** Handle incoming URLs in your `SceneDelegate` or `AppDelegate`. For detailed
instructions and code examples, see Apple's
[Handling incoming URLs](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app#Handle-incoming-URLs).

## Handle universal links

> Note: Full trackable universal link support is available in SDK version 5.1.0 and later.

Klaviyo supports embedding
[universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
with click tracking in emails. To make sure universal links are tracked as profile events *and* that
your app opens and processes them correctly, configure your app to handle them. At a high level:

1. A marketer includes a universal link in a Klaviyo email. Klaviyo automatically wraps it in a
   unique, trackable URL, which we call a **universal tracking link**.
2. When a user taps the link on a device with your app installed, iOS delivers the wrapped link to
   your app.
3. Your app passes the universal tracking link to the SDK by calling
   ``KlaviyoSDK/handleUniversalTrackingLink(_:)``.
4. The SDK records a click event on the user's profile and unwraps the universal tracking link into
   the *original* universal link.
5. The SDK then processes the original link in one of two ways:
   - **Preferred:** it passes the link to the deep link handler you registered with
     ``KlaviyoSDK/registerDeepLinkHandler(_:)``. This gives you full control over navigation.
   - **Fallback:** it passes the link back to your `AppDelegate` or `SceneDelegate`, invoking the
     URL-handling logic you've written there.

The steps below also let your app handle standard universal links (links that aren't Klaviyo
universal tracking links).

> Warning: These instructions diverge somewhat from
> [Apple's documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
> on supporting universal links.

### Step 1: Configure universal links in your Klaviyo account

Follow Klaviyo's guide to
[setting up universal links](https://help.klaviyo.com/hc/en-us/articles/41701832186523) in your
Klaviyo account.

### Step 2: Add the Associated Domains entitlement

Follow Apple's documentation to
[add the associated domains entitlement to your app](https://developer.apple.com/documentation/xcode/supporting-associated-domains#Add-the-associated-domains-entitlement-to-your-app).

Add the universal link domain you configured in step 1, prefixed with `applinks:`. For example:

`applinks:mycompany.com`

### Step 3 (recommended): Register a deep link handler

A registered handler gives you one reliable place to handle incoming links from Klaviyo and
simplifies your app's logic. The SDK has a fallback if you don't register one, but a handler makes
your code more stable, more resilient to iOS changes, and simpler.

Where you initialize the SDK (see <doc:GettingStarted#Initialize-the-SDK>), call
``KlaviyoSDK/registerDeepLinkHandler(_:)`` with a closure that handles the URL:

```swift
import KlaviyoSwift

// Chained with initialization
KlaviyoSDK()
    .initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
    .registerDeepLinkHandler { url in
        // Your code to parse the URL and use the result to navigate to a specific screen
        // if you created a helper method (see "Add link-handling logic", above), call it here
    }

// **Or** called separately after initialization
KlaviyoSDK().registerDeepLinkHandler { url in
    // Your code to parse the URL and use the result to navigate to a specific screen
    // if you created a helper method (see "Add link-handling logic", above), call it here
}
```

The same handler receives deep links from push notifications and in-app forms. To remove it, call
``KlaviyoSDK/unregisterDeepLinkHandler()``.

### Step 4: Pass the universal tracking link to the SDK

Pass the incoming universal tracking link URL from the `NSUserActivity` object to the SDK by calling
``KlaviyoSDK/handleUniversalTrackingLink(_:)``. The method returns `true` synchronously if the link
is a valid Klaviyo universal tracking link. If it returns `false`, the link isn't a Klaviyo universal
tracking link, and you should handle it yourself.

**If your app uses an AppDelegate** (see below if your app uses a `SceneDelegate`): when the user
opens a Klaviyo universal tracking link, the system delivers it to the app delegate's
[`application(_:continue:restorationHandler:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:continue:restorationhandler:))
method. Extract the link from the `NSUserActivity` and pass it to
`KlaviyoSDK().handleUniversalTrackingLink(_:)`. For example:

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    // Get the URL from the incoming user activity.
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
        let incomingURL = userActivity.webpageURL
    else {
        return false
    }

    if KlaviyoSDK().handleUniversalTrackingLink(incomingURL) {
        return true
    } else {
        // handle a link that's not a Klaviyo universal tracking link
        // if you created a helper method (see "Add link-handling logic", above), call it here
        return false
    }
}
```

**If you've opted into scenes:** the system delivers the universal tracking link to one of two
`SceneDelegate` methods, depending on the app's state.

- If the app is terminated, the system delivers the link to
  [`scene(_:willConnectTo:options:)`](https://developer.apple.com/documentation/UIKit/UISceneDelegate/scene(_:willConnectTo:options:))
  after launch.
- If the app is running or in the background, the system delivers the link to
  [`scene(_:continue:)`](https://developer.apple.com/documentation/UIKit/UISceneDelegate/scene(_:continue:)).

In *both* methods, extract the link from the `NSUserActivity` and pass it to
`KlaviyoSDK().handleUniversalTrackingLink(_:)`. For example:

```swift
func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
) {
    // Get the URL from the incoming user activity.
    guard let userActivity = connectionOptions.userActivities.first,
        userActivity.activityType == NSUserActivityTypeBrowsingWeb,
        let incomingURL = userActivity.webpageURL
    else {
        return
    }

    if KlaviyoSDK().handleUniversalTrackingLink(incomingURL) {
        return
    } else {
        // handle a link that's not a Klaviyo universal tracking link
        // if you created a helper method (see "Add link-handling logic", above), call it here
    }
}

func scene(
    _ scene: UIScene,
    continue userActivity: NSUserActivity
) {
    // Get the URL from the incoming user activity.
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let incomingURL = userActivity.webpageURL
    else {
        return
    }

    if KlaviyoSDK().handleUniversalTrackingLink(incomingURL) {
        return
    } else {
        // handle a link that's not a Klaviyo universal tracking link
        // if you created a helper method (see "Add link-handling logic", above), call it here
    }
}
```

## Validate your setup

To validate your deep linking setup, send a push notification from the Klaviyo push editor. You can
configure it to trigger a deep link through either a URL scheme or a universal link. Open the
notification on your device and check that the link is handled by the logic you wrote in
<doc:DeepLinking#Add-link-handling-logic>.

To validate that Klaviyo universal tracking links work, create a test email campaign in Klaviyo that
includes a universal link matching the domain you configured in
<doc:DeepLinking#Step-1-Configure-universal-links-in-your-Klaviyo-account>. Send the campaign and
copy the link from the email. Open the link on your device and check that it's handled by the logic
you wrote in <doc:DeepLinking#Add-link-handling-logic>.

You can also trigger a deep link locally in the Simulator with this Terminal command:

`xcrun simctl openurl booted {your_URL_here}`
