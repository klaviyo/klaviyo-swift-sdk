# Advanced Topics

Sandbox push, logging, and how the SDK sends and retries data.

## Overview

These details don't require any setup, but they help you understand and debug how the SDK behaves.

## Sandbox support

> Note: Sandbox support is available in SDK version
> [2.2.0](https://github.com/klaviyo/klaviyo-swift-sdk/releases/tag/2.2.0) and later.

Apple has two environments with push notification support: Production and Sandbox. The Production
environment sends push notifications to real users when an app is published in the App Store or
TestFlight. Sandbox apps are those signed with iOS Development Certificates instead of iOS
Distribution Certificates. Sandbox acts as a staging environment: you can test your app in an
environment similar to, but separate from, Production without sending messages to real users.

The SDK supports Sandbox push too. It determines and stores the environment your push token belongs
to and sends it to Klaviyo, so sends are routed to the correct environment. No additional setup is
needed. As long as you've deployed your app to Sandbox with the SDK sending push tokens to Klaviyo,
sending and receiving push on Sandbox apps works out of the box.

## Logging

The SDK logs diagnostic information to the system console through `os.Logger`. Logging is on by
default, and you can toggle it at runtime with ``KlaviyoSDK/setLoggingEnabled(_:)`` and check it
with ``KlaviyoSDK/isLoggingEnabled``:

```swift
KlaviyoSDK().setLoggingEnabled(false) // silence all SDK logging
KlaviyoSDK().setLoggingEnabled(true)  // re-enable logging
KlaviyoSDK().isLoggingEnabled         // check the current setting
```

Turning logging off silences all log output from the `KlaviyoSwift`, `KlaviyoCore`, `KlaviyoForms`
and `KlaviyoLocation` modules. It doesn't affect `KlaviyoSwiftExtension`, which runs in a separate
app extension process.

## SDK data transfer

Starting with version 1.7.0, the SDK caches incoming data and flushes it to the Klaviyo API on an
interval. The interval depends on the network link the app is currently using:

| Network | Interval |
|:--|:--|
| Wi-Fi | 10 seconds |
| Cellular (WWAN) | 30 seconds |

The connection type comes from the SDK's reachability service. When no network is available, the
SDK caches data until the network is available again. Data sent by the SDK should be available in
Klaviyo shortly after the SDK flushes it.

## Retries

The SDK retries API requests that fail under certain conditions. For example, if a network timeout
occurs, the request is retried on the next flush interval. If the SDK receives a `429` rate-limiting
error or a transient `5xx` server error from the Klaviyo API, it retries with exponential backoff
plus jitter, and honors the server's `Retry-After` header when it asks for a longer wait.
