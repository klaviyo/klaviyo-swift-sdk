# KlaviyoSwift

[![CI Status](http://img.shields.io/travis/Katy Keuper/KlaviyoSwift.svg?style=flat)](https://travis-ci.org/Katy Keuper/KlaviyoSwift)
[![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![License](https://img.shields.io/cocoapods/l/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)
[![Platform](https://img.shields.io/cocoapods/p/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift)

## Overview

KlaviyoSwift is an SDK, written in Swift, for users to incorporate Klaviyo's event tracking functionality into iOS applications. We also provide an SDK written in [Objective-C](https://github.com/klaviyo/klaviyo-objc-sdk). The two SDKs are identical in their functionality.

## Requirements
*iOS 8.0
*Swift 2.0 & XCode 7.0

## Installation with CocoaPods

KlaviyoSwift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "KlaviyoSwift"
```

## Usage

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Special Properties

Referencing special people and event properties works in a similar manner to the [Klaviyo Analytics API](https://www.klaviyo.com/docs). These are special properties that can be utilized when identifying a user. They are:
    
    *$email
    *$first_name
    *$last_name
    *$phone_number
    *$title
    *$organization
    *$city
    *$region
    *$country
    *$zip

## Author

Katy Keuper, katy.keuper@klaviyo.com

## License

KlaviyoSwift is available under the MIT license. See the LICENSE file for more info.
