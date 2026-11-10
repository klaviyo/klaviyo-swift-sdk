# Geofencing

Track geofence enter and exit events for the regions configured in your Klaviyo account.

## Overview

> Note: Geofencing is available in SDK version 5.2.0 and later.

[Geofencing](https://help.klaviyo.com/hc/en-us/articles/45194892526747) lets you trigger events
when users enter or exit geographic regions. The SDK monitors the geofences configured in your
Klaviyo account and automatically tracks geofence enter and exit events. It also keeps geofences in
sync with your Klaviyo account: when you add, update or remove geofences in Klaviyo, the SDK picks
up the changes on the next app launch or when the API key changes.

> Important: Geofencing requires "Always" location authorization and "Precise" accuracy. The SDK
> only starts monitoring geofences once the user grants these permissions. By default, a user who
> grants location authorization grants it with "Precise" accuracy unless they change it. If the user
> only grants, or later downgrades to, "When In Use" permission, geofencing isn't active.

### Prerequisites

- `KlaviyoSwift` and `KlaviyoLocation` added to your app target. See
  [Getting Started](/documentation/klaviyoswift/gettingstarted).
- Location permissions and background modes configured in your app's `Info.plist`.
- "Always" location authorization requested from users.

## Set up geofencing

### Step 1: Configure Info.plist

Add the following keys to your app's `Info.plist`.

**Location usage descriptions** (required):

- `NSLocationWhenInUseUsageDescription`, for example: "Your location helps the app offer
  location-based features and notifications while you're using it."
- `NSLocationAlwaysAndWhenInUseUsageDescription`, for example: "This app uses your location in the
  background to detect when you enter or leave specific areas and send you relevant notifications."

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to show your current location and help you find nearby locations.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs location access to monitor geofences and provide location-based notifications when the app is in the background.</string>
```

**Background modes** (required): add `location` to the `UIBackgroundModes` array to enable
background location updates.

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

> Note: Adding the location usage keys and the location background mode to your `Info.plist`
> requires additional justification when you submit to the App Store. See sections 2.5.4 and 5.1.5
> of Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

### Step 2: Request location authorization

Request location authorization according to
[Apple's guidelines](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()#Request-Always-Authorization-After-Getting-When-In-Use).
Apple recommends requesting "When In Use" authorization first, and "Always" authorization later. We
strongly suggest following Apple's best practices for requesting location permissions. The example
app shows
[one way to set up this call](https://github.com/klaviyo/klaviyo-swift-sdk/blob/97b53ac6d314035a1c8cf639565d9b0ab7e83add/Examples/KlaviyoSwiftExamples/Shared/MapView.swift#L406).

### Step 3: Register for geofencing

Call ``KlaviyoCore/KlaviyoSDKModule/registerGeofencing()`` as early as possible in your app's life
cycle, ideally right after initializing the SDK. This method:

- starts monitoring the geofences configured in your Klaviyo account, and
- starts tracking geofence enter and exit events.

```swift
// AppDelegate

import KlaviyoSwift
import KlaviyoLocation

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        KlaviyoSDK()
            .initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
            .registerGeofencing()
        return true
    }
}
```

We **strongly recommend** registering for geofencing in `didFinishLaunchingWithOptions`, so that
all enter and exit events are delivered to Klaviyo whatever the app's state (backgrounded or
terminated).

## Unregister from geofencing

To stop monitoring geofences, call ``KlaviyoCore/KlaviyoSDKModule/unregisterGeofencing()``:

```swift
import KlaviyoSwift
import KlaviyoLocation

KlaviyoSDK().unregisterGeofencing()
```
