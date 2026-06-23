# 😂😂😂 klaviyo-swift-sdk 😂😂😂
### 🍝 *the readme that asked "what if documentation but unhinged"* 🍝

![CI status](https://github.com/klaviyo/klaviyo-swift-sdk/actions/workflows/swift.yml/badge.svg) [![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square) ![SPM version](https://img.shields.io/github/v/release/klaviyo/klaviyo-swift-sdk) [![Version](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift) [![License](https://img.shields.io/cocoapods/v/KlaviyoSwift.svg?style=flat)](http://cocoapods.org/pods/KlaviyoSwift) ![Minimum deployment version](https://img.shields.io/badge/minimum_iOS_deployment_target-iOS13-brightgreen)

> 🚨🚨🚨 **SCROLL PAST THIS MESSAGE** 🚨🚨🚨
>
> ✋ STOP ✋ you are about to read documentation ✋
> 🧠 this is normal 🧠 you are safe 🧠 breathe 🧘
> 🍝 this readme contains: **603+ emojis** 🍝 **0 regrets** 😌 **1 legal section** ⚖️
> 📜 by scrolling past this point you agree that 📜:
> &nbsp;&nbsp;&nbsp;&nbsp; 🐦 swift is a good language 🐦
> &nbsp;&nbsp;&nbsp;&nbsp; 😂 this sdk is very cool 😂
> &nbsp;&nbsp;&nbsp;&nbsp; 🫵 you will integrate it today 🫵
>
> 🫡 thank you for your compliance 🫡

---

## 🗺️ table of contents (the map to the treasure 🏴‍☠️)

- 👁️ [overview (what even IS this)](#-overview-what-even-is-this-)
- 📦 [installation (the necessary evil)](#-installation-the-necessary-evil-)
- 🚀 [initialization (the one line that starts it all)](#-initialization-the-one-line-that-starts-it-all-)
- 🪪 [who even ARE you (profile identification)](#-who-even-are-you-profile-identification-)
  - 🔄 [bye bestie (reset profile)](#-bye-bestie-reset-profile-)
  - 👻 [anonymous gremlin mode](#-anonymous-gremlin-mode-)
- 📊 [they did a thing!! (event tracking)](#-they-did-a-thing-event-tracking-)
- 🔔 [the boop (push notifications)](#-the-boop-push-notifications-)
  - ✅ [prerequisites (ugh)](#-prerequisites-ugh-)
  - 🪙 [gotta catch em all (push tokens)](#-gotta-catch-em-all-push-tokens-)
  - 🙏 [pretty please (asking for permission)](#-pretty-please-asking-for-permission-)
  - 📬 [receiving the boop](#-receiving-the-boop-)
    - 👆👆👆 [THEY TAPPED IT OMG](#-they-tapped-it-omg-)
    - 🕳️ [go deeper (deep linking)](#-go-deeper-deep-linking-)
    - 🖼️ [fancy boop (rich push)](#-fancy-boop-rich-push-)
    - 😰 [the lil red circle of anxiety (badge count)](#-the-lil-red-circle-of-anxiety-badge-count-)
    - 🫥 [sneaky ghost boop (silent push)](#-sneaky-ghost-boop-silent-push-)
    - 🎁 [there's more inside (custom data)](#-theres-more-inside-custom-data-)
- 💅 [pop-ups but make them slay (in-app forms)](#-pop-ups-but-make-them-slay-in-app-forms-)
- 🔬 [nerd corner](#-nerd-corner-)
  - 🏖️ [the simulation (sandbox)](#-the-simulation-sandbox-)
  - 🚿 [the flush (data transfer)](#-the-flush-data-transfer-)
  - 🔁 [try again bestie (retries)](#-try-again-bestie-retries-)
  - ⚖️ [the legal blorbo (license)](#-the-legal-blorbo-license-)
- 🆘 [help me (contributing / issues)](#-help-me-)

---

## 👁️ overview (what even IS this) 👁️

> 🧠💭 *okay so*
> 🧠💭 *you have an iOS app* 📱
> 🧠💭 *and you want to know what your users are doing* 🕵️
> 🧠💭 *and you want to send them little boops* 🔔
> 🧠💭 *and you want to show them pop-ups* 📋
> 🧠💭 *and you don't want to write all that yourself* 😮‍💨
> 🧠💭 ***hello*** 👋

the 😂 **klaviyo swift sdk** 😂 does these exact things:

```
🥇  TRACK EVENTS      →  "oh interesting, they added to cart" 🛒
🥈  IDENTIFY USERS    →  "who ARE you. what is your email. I must know" 🪪
🥉  PUSH TOKENS       →  "collect the little hex string that lets us boop them" 🪙
🏅  IN-APP FORMS      →  "interrupt them mid-scroll with a tasteful offer" 📋
```

🌊 api calls are **queued** then **batched** 🫙 like little data gnocchi being lovingly portioned into pasta shapes 🍝
💾 **persisted to disk** 💾 so even if the phone 📱 dies mid-session, falls in a toilet 🚽, or travels internationally ✈️ — your data SURVIVES 💪
📡 your 🎯 marketing team 🎯 will be able to understand what users 👥 actually want 👥 and send them perfectly timed 💌 messages via APNs 🍎 instead of just vibes 🌈

---

## 📦 installation (the necessary evil) 📦

> 😤 "but I don't WANT to set things up" 😤
> 🫂 we know 🫂 we're sorry 🫂 it takes like 5 minutes 🕐 you've survived worse 🦾

### 🐾 step uno: enable push capabilities 🐾

🍎 open xcode 🍎
🔧 turn on push notification capabilities 🔧
📖 [apple explains this better than we do](https://developer.apple.com/documentation/usernotifications/registering_your_app_with_apns#2980170) 📖 honestly just click that link 🔗

    ### 🐾 step dos: notification service extension 🐾A
> 💀💀💀 **STOP RIGHT HERE** 💀💀💀
>
> ⚠️ the extension's deployment target defaults to the **LATEST iOS version** ⚠️
> ⚠️ if that's newer than your app's minimum iOS version ⚠️
> ⚠️ then your users on older phones 📱 will NOT see rich push images 📸 ⚠️
> ⚠️ they will see a sad, imageless notification 😭 ⚠️
> ⚠️ and it will be YOUR fault ⚠️
> ⚠️ **MATCH THE DEPLOYMENT TARGETS** ⚠️
> ⚠️ you have been warned ⚠️

🤝 now buddy your two targets together with an **App Group** 🤝:

```
☑️  main app → Signing & Capabilities → ➕ Capability → App Groups
☑️  create: group.[YourBundleId].somethingDescriptive
☑️  Info.plist (main app)  → add key "klaviyo_app_group" → String → your group name 🗝️
☑️  add the SAME group name to your extension target too 🔗
☑️  Info.plist (extension) → also add "klaviyo_app_group" → same value 🗝️
☑️  yes both. yes the same value. yes again. trust.
```

### 🐾 step tres: pick your poison 📦 🐾

<details>
<summary>✨🍺 Swift Package Manager 🍺✨ — (THE GOOD ONE. DO THIS. CLICK HERE.)</summary>

> 🌈 **CONGRATULATIONS** 🌈
> you have chosen correctly 🏆
> you are a person of culture 🎩

1️⃣ 📂 open project → ⚙️ project settings → 📋 **Package Dependencies** tab
2️⃣ hit the ➕ like you mean it
3️⃣ paste this beautiful URL 🤌:
```
https://github.com/klaviyo/klaviyo-swift-sdk
```
4️⃣ rule: **Up to Next Major Version** 📈
&nbsp;&nbsp;&nbsp; (the numbers are pre-filled. don't touch them. they're fine. leave them alone. 🚫🔢)
5️⃣ **Add Package** 🎁
6️⃣ assign like so:
```
📱  your app target   →  KlaviyoSwift ✅   KlaviyoForms ✅
🔔  notif extension   →  KlaviyoSwiftExtension ✅
```
7️⃣ **Add Package** again because xcode needs to hear it twice 🎁🎁
🎉 **YOU DID IT!! IT'S INSTALLED!! LOOK AT YOU GO!!** 🎉

</details>

<details>
<summary>🫙 CocoaPods — (we see you out there. we aren't judging. much. okay a little.)</summary>

> 💅 still on pods huh 💅
> that's fine 💅
> no really 💅
> totally fine 💅
> ...
> anyway here's your podfile 😌:

```ruby
target 'YourAppTarget' do        # 🎯 hello, your app
  pod 'KlaviyoSwift'             # 🐦 the main character
end

target 'YourAppTarget' do        # 🎯 yes again, same target, I know
  pod 'KlaviyoForms'             # 📋 the forms slay
end

target 'YourNotifExtension' do   # 🔔 the lil notification buddy
  pod 'KlaviyoSwiftExtension'    # 🔌 plug it in plug it in
end
```

```bash
pod install    # 🫞 pour it in. slurp it up. let it wash over you.
```

🔄 to update when we ship new things:
```bash
pod update KlaviyoSwift          # 🔄 fresh
pod update KlaviyoSwiftExtension # 🔄 also fresh
```

> 🫡 godspeed 🫡

</details>

### 🐾 step cuatro: copy this file 📄 🐾

📋 take the code from [NotificationService.swift](Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift)
🖱️ paste it into your `NotificationService.swift`
🖼️ it handles: rich media 🖼️ badge counts 🔴 custom data 🎁
🧪 it just works. trust the process. 🧘

> 🔬 **NERD NOTE** 🔬
> using multiple push providers 🤹 and need to know which notifications are ours?
> `import KlaviyoSwift` → check `isKlaviyoNotification` on any `UNNotificationResponse`
> it's a bool 👍 or 👎 very binary very binary

---

## 🚀 initialization (the one line that starts it all) 🚀

> 🗝️ you need your **public API key** 🗝️
> 🏷️ also called your **Site ID** 🏷️
> 🖥️ lives on your klaviyo dashboard 🖥️
> 🔡 looks like someone sneezed on a keyboard 🔡 this is correct 🔡

```swift
// 📂 AppDelegate.swift
// 🐣 this is where apps are born. this is where the magic begins. this is the hatching.

import KlaviyoSwift  // 👈 this import. right here. do not forget this import.

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")
        //                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^
        //                      🔑 put your ACTUAL key here not this string 🔑
        //                      🔑 "YOUR_KLAVIYO_PUBLIC_API_KEY" will not work 🔑
        //                      🔑 we have seen people ship "YOUR_KLAVIYO_PUBLIC_API_KEY" 🔑
        //                      🔑 you know who you are 🔑
        //                      🔑 please 🔑

        return true  // ✅ launched. stable. alive. doing great.
    }
}
```

🚨 **THE RULE** 🚨 initialize **BEFORE** all other SDK calls 🚨
🚨 if you call other SDK methods before initializing 🚨
🚨 the SDK will not crash 🚨 but it will do nothing 🚨
🚨 and you will spend 3 hours debugging 🚨
🚨 and it will be fine actually but still 🚨
🚨 **just do it first** 🚨

---

## 🪪 who even ARE you (profile identification) 🪪

> 🔭 the SDK can identify your users as Klaviyo profiles 🔭
> via the [Create Client Profile API](https://developers.klaviyo.com/en/reference/create_client_profile) 📡
> you can identify someone by:

```
🪪  external ID     →  some ID from your backend 🏢 (could be a UUID 🔢, a username 👤, whatever)
📧  email           →  the @ address 📮 (classic)
📞  phone number    →  E.164 format ONLY ☎️ (+15551234567 ✅  5551234567 ❌  "their phone" ❌❌❌)
```

💾 these stick around in **local storage** 💾
🧠 the SDK holds onto them across sessions like a diligent lil archivist 🗂️
📦 batches API calls together like a responsible adult who does their laundry once a week 👏

### 👤 introducing a whole entire human person 👤

```swift
// 🎭 act one: the arrival of blob jr. 🎭
// (blob jr. is our beloved sdk documentation character. they have been with us since the beginning.)
let profile = Profile(
    email: "junior@blob.com",       // 📧 the @ address
    firstName: "Blob",              // 👆 first name (such a strong name)
    lastName: "Jr."                 // 👇 last name (carries on the blob legacy)
    // bonus fields you can also set 🎁:
    //   organization: "Blob Industries LLC" 🏢
    //   title: "Chief Blob Officer" 💼
    //   image: "https://example.com/blob.jpg" 🖼️
    //   location: Location(city: "Blobville") 📍
    //   properties: ["favorite_food": "gnocchi"] 📚
)
KlaviyoSDK().set(profile: profile)  // 📤 whoosh. blob jr. is now in klaviyo.

// OR set fields one at a time, à la carte 🍽️:
KlaviyoSDK().set(profileAttribute: .firstName, value: "Blob")  // 👆 hello blob
KlaviyoSDK().set(profileAttribute: .lastName, value: "Jr.")    // 👇 hello jr.
// 🔄 these get batched together anyway. the sdk is smart like that.
```

### 🔄 bye bestie (reset profile) 🔄

> 👋 is your user logging out? 👋
> you MUST reset or the next user will inherit blob jr.'s entire profile 😱
> blob jr. worked hard for that profile 😤 it belongs to blob jr. 😤

```swift
// 📖 the complete lifecycle of blob jr. in your app 📖

// 🌅 chapter 1: blob jr. shows up (hi bestie 🤗)
let blobJr = Profile(email: "junior@blob.com", firstName: "Blob", lastName: "Jr.")
KlaviyoSDK().set(profile: blobJr)

// 🌇 chapter 2: blob jr. peaces out (goodbye forever 👋😢)
KlaviyoSDK().resetProfile()
// ☝️ nukes all identifiers 🧹
// ☝️ push token gets passed to a new anonymous profile 👻 (token not lost! just rehomed 🏠)
// ☝️ do NOT skip this on logout. do NOT. we cannot stress this enough.

// 🌅 chapter 3: a new challenger appears (welcome robin 🏹)
let robin = Profile(email: "robin@hood.com", firstName: "Robin", lastName: "Hood")
KlaviyoSDK().set(profile: robin)
// (robin has absolutely NO idea blob jr. was ever here. as it should be.)
```

### 👻 anonymous gremlin mode 👻

> 🌑 sometimes you don't know who the user is yet 🌑
> maybe they haven't logged in 🤷
> maybe they're just vibing 🌊
> maybe they're a little gremlin who refuses to give you their email 😤
>
> 🤫 here's the secret 🤫
> klaviyo gives them an **autogenerated anonymous ID** automatically 🤖
> events + push tokens get quietly collected in the dark 🌑
> when they FINALLY identify themselves 📧 we merge the anonymous profile into the real one 🤝
> all those events they did as a gremlin? 👻 **kept** 📂
> all those push tokens they accumulated? 🪙 **kept** 📂
> no data is ever lost to gremlinhood 💪

---

## 📊 they did a thing!! (event tracking) 📊

> 🎺 your users are OUT THERE 🎺
> 🎺 doing THINGS in your app 🎺
> 🎺 clicking buttons!! viewing products!! adding to cart!! 🎺
> 🎺 and you can KNOW about ALL of it 🎺
> 🎺 via the [Create Client Event API](https://developers.klaviyo.com/en/reference/create_client_event) 📡 🎺

```swift
// 💳 THEY'RE CHECKING OUT!!! LOG EVERYTHING!!! 💳
let bigSpender = Event(
    name: .startedCheckoutMetric,     // 💳 one of our fancy prebuilt metric names
    properties: [
        "item_name": "extremely cool t-shirt",  // 👕 what they're buying
        "color":     "vantablack",              // 🖤 very dark. very cool.
        "size":      "extra swag",              // 😎 non-standard sizing but okay
        "vibes":     "immaculate",              // ✨ custom props go here
    ],
    value: 166  // 💰 one hundred and sixty six dollars for a shirt. respect.
)
KlaviyoSDK().create(event: bigSpender)  // 📤 sent to klaviyo. logged. witnessed.

// 🎯 custom event — name it whatever you want, we don't gatekeep 🎯
let cryptidEvent = Event(
    name: .customEvent("User Stared At The Home Screen For 47 Minutes Without Moving"),
    properties: [
        "was_blinking":          false,  // 😶 confirmed
        "concerning":            true,   // 😰 extremely
        "contacted_their_mom":   false,  // 📵 no
        "should_we_send_a_push": true,   // 📲 probably yes
    ],
    value: 0  // 💸 no purchase. just vibes.
)
KlaviyoSDK().create(event: cryptidEvent)  // 📤 noted. flagged. praying for them.
```

### 📋 event constructor cheat sheet 📋

| argument | required? | what it is |
|---|---|---|
| `name` 📛 | ✅ yes bestie | an `Event.EventName` — pick a prebuilt one or do `.customEvent("whatever")` |
| `properties` 📚 | 🤷 nah | a `[String: Any]` dict of extra context. go wild. |
| `value` 💰 | 🤷 nah | a `Double`. usually money 💵. technically anything. |

#### 🎪 the prebuilt event buffet 🎪

```swift
.openedAppMetric        // 📱 they opened the app. humble. classic. foundational.
.viewedProductMetric    // 👀 window shopping detected
.addedToCartMetric      // 🛒 interest is high. conversion pending.
.startedCheckoutMetric  // 💳 this is it. this is the moment.
.customEvent("💅")      // 🎯 you name it. we track it. no rules here.
```

---

## 🔔 the boop (push notifications) 🔔

> 📲 the boop 📲
> *booooop* 📲
> that little thing that taps your shoulder and says "hey" 👋
> even when the app is closed 🚪
> incredible technology really 🤯

### ✅ prerequisites (ugh) ✅

- 🍎 [apple developer account](https://developer.apple.com/) — yes you pay $99/year to apple 💸 this is the deal we made with them 🤝
- ⚙️ [configure iOS push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971) in your Klaviyo account 🔧

### 🪙 gotta catch em all (push tokens) 🪙

> 🎣 a push token 🎣
> is a long hexadecimal string 🔡
> that is basically the user's home address 🏠 but for notifications 📲
> apple 🍎 mints one for each device/app combo
> and hands it to you in a delegate method
> and you hand it to us
> and we keep it safe forever 🗄️
> the circle of life 🦁🌿

```swift
import KlaviyoSwift  // 👈 you know the drill

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {

    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")  // 🚀 step 1

    UIApplication.shared.registerForRemoteNotifications()
    // ☝️ this calls up to apple 🍎 and goes
    // ☝️ "hello apple we would like a push token please 🙏"
    // ☝️ apple considers it
    // ☝️ apple says "fine" 🍎
    // ☝️ the next method gets called

    return true  // ✅
}

func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data  // 🪙 here's the token!
) {
    KlaviyoSDK().set(pushToken: deviceToken)  // 🤲 take the token. cherish it. send it to us.
}
```

### 🙏 pretty please (asking for permission) 🙏

> 👆 you have the token 👆
> 🙅 but iOS requires user **permission** before you can actually show them notifications 🙅
> 🥺 you must ask 🥺
> 🥺 with your whole chest 🥺
> 🥺 please 🥺
>
> 📖 apple has [guidelines](https://developer.apple.com/documentation/usernotifications/asking_permission_to_use_notifications) on when to ask 📖
> 🚫 do NOT ask on first launch 🚫 you will scare them and they will say no 😱
> ✅ ask after they've seen value in the app ✅ when it makes sense ✅

```swift
import UserNotifications  // 🔔

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {

    KlaviyoSDK().initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")  // 🚀
    UIApplication.shared.registerForRemoteNotifications()         // 🪙

    let center = UNUserNotificationCenter.current()
    center.delegate = self as? UNUserNotificationCenterDelegate   // 🤝 register yourself as delegate

    let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    // 🤫 SPICY OPTION: add .provisional to silently deliver to notification center
    //    without ever prompting the user. sneaky. controversial. powerful.
    //    some call it evil. some call it genius. only you can decide. 😈

    center.requestAuthorization(options: options) { granted, error in
        if let error = error {
            print("😭 permission request blew up: \(error)")
        }
        // 🙏 whether they said yes OR no, call this:
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
            // ☝️ ensures klaviyo always has the latest authorization status 🌿
            // ☝️ even if it changed since last time 🔄
        }
    }

    return true  // ✅
}
```

> 🤖 after a token is set 🤖
> the SDK **automatically tracks** auth status changes from that point on
> on every app open 🌅 and every background resume 🌄
> zero extra code from you 🪄 we got it 🤙

### 📬 receiving the boop 📬

#### 👆👆👆 THEY TAPPED IT OMG 👆👆👆

> 🥁 *drumroll* 🥁
> a user has seen your notification 👁️
> considered it 🤔
> and TAPPED it 👆
> this is the dream. this is what we're here for.
> track it immediately. do not let this moment pass unrecorded. 📊

```swift
// 👇 make sure you set center.delegate = self somewhere (see permission section ☝️)
extension AppDelegate: UNUserNotificationCenterDelegate {

    // 🌚 user tapped while app was backgrounded / device locked
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let handled = KlaviyoSDK().handle(
            notificationResponse: response,
            withCompletionHandler: completionHandler
        )
        // 😂 if it's a klaviyo notification:
        //      ✅ tracks the "Opened Push" event
        //      ✅ handles the deep link if there is one
        //      ✅ calls completionHandler on the main thread
        //      ✅ does everything. you're done.
        // 🤷 if it's NOT a klaviyo notification:
        //      → handled == false → you handle it → not our circus 🎪
        if !handled {
            completionHandler()
        }
    }

    // 🌞 notification arrived while app was ALREADY open (foreground)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.list, .banner])  // 📋 ye modern banner + list combo
        } else {
            completionHandler([.alert])          // 📢 the old ways. classic.
        }
    }
}
```

> 🎉 send a push → user taps it → behold **Opened Push** in your Klaviyo dashboard 📊
> it feels like magic 🪄 it is not magic 🪄 it is just JSON being sent over HTTPS 🔐
> but also it's a little bit magic 🪄

#### 🕳️ go deeper (deep linking) 🕳️

> ℹ️ needs SDK **v1.7.2+** ℹ️

> 🌀 **DEEP LINKS** 🌀
> instead of just opening your app to the home screen 🏠
> they teleport the user directly to a specific screen 📱
> like if someone sent you a letter and it opened into a room 🚪
> never mind. it's like clicking a hyperlink. but for apps. 🔗

**two roads diverged in a plist** 🍃, and you may only choose one:

##### 🅰️ path one: URL schemes (old faithful) 🅰️

**1️⃣ tell the system what scheme you own** (in `Info.plist`):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>                   <!-- ✏️ you edit things. you are the editor. -->
        <key>CFBundleURLName</key>
        <string>com.yourcompany.yourapp</string>  <!-- 🪪 reverse-dns. uniqueness. professionalism. -->
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>              <!-- 🔗 yourapp://whatever gets sent here -->
        </array>
    </dict>
</array>
```

**2️⃣ also whitelist it** (iOS 9+ requires this. don't ask why. it's apple.):

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>yourapp</string>  <!-- 🗝️ yes you list it twice. yes in two different places. -->
</array>                       <!-- 🗝️ it's fine. this is fine. everything is fine. 🔥 -->
```

**3️⃣ handle the URL when it arrives**:

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else {
        print("💀 broken URL. someone sent us nonsense. logging and moving on.")
        return false
    }
    print("🕳️ deep link received: \(components.debugDescription)")
    // 🗺️ use components to figure out where to navigate
    // 🗺️ the implementation of that navigation is your business not ours
    return true  // ✅ handled. done. good job.
}
```

> 🌿 **SwiftUI people** 🌿 your way is nicer tbh:
```swift
@main
struct MyApplication: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // 🔗 same deal. url arrives here. you navigate. fin.
                }
        }
    }
}
```

> 🧪 test without a real push, right in terminal:
> ```bash
> xcrun simctl openurl booted yourapp://the-screen-you-want
> # 💥 boom. simulated deep link. no push required. very satisfying.
> ```

##### 🅱️ path two: universal links (fancy mode) 🅱️

> 🌐 basically HTTP/S links that open in your app instead of Safari 🌐
> 🔒 more secure 🔒 better UX 💅 requires more setup 😮‍💨
> 🖥️ you need an `apple-app-site-association` file on a real web server 🖥️
> 📖 [do the apple setup first](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html) 📖 come back when you're done 👈

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let handled = KlaviyoSDK().handle(
            notificationResponse: response,
            withCompletionHandler: completionHandler
        ) { url in
            // 🔗 this closure fires with the actual destination URL
            // 🔗 the one that klaviyo resolved from the tracking link
            // 🔗 do your navigation here
            print("🕳️ navigating to: \(url)")
        }
        if !handled {
            // 🤷 wasn't ours. handle it yourself. we believe in you.
        }
    }
}
```

> 📌 tiny but important note 📌
> the deep link handler closure is called on the **main thread** 🧵
> not a background thread 🌑 the **main** thread 🌞
> please plan accordingly 🙏

#### 🖼️ fancy boop (rich push) 🖼️

> ℹ️ needs SDK **v2.2.0+** ℹ️

> 📸 a plain text push notification is fine 📸
> but a push notification with a **beautiful image** attached? 📸
> *chef's kiss* 🤌
> people click those WAY more 📊 (the data is in on this one)

as long as your notification service extension is set up 🔌
`KlaviyoSwiftExtension` downloads and attaches the image automatically 🤖
you don't even have to look at the code 🙈 it just works 🪄

🧪 to test locally:

1️⃣ get a push testing tool 📲 — [apple's official console](https://developer.apple.com/notifications/push-notifications-console/) or [this delightful third-party one](https://github.com/onmyway133/PushNotifications)
2️⃣ fire this payload at your device 🎯:

```json
{
  "aps": {
    "alert": {
      "title": "WOW LOOK AT THIS 😍",
      "body": "so rich. much media. very wow. 🐕"
    },
    "mutable-content": 1
  },
  "rich-media": "https://picsum.photos/200/300.jpg",
  "rich-media-type": "jpg"
}
```

3️⃣ get your device's push token from `didRegisterForRemoteNotificationsWithDeviceToken` 🪙
4️⃣ 🚀 launch 🚀
5️⃣ 🖼️ *look upon your creation* 🖼️

#### 😰 the lil red circle of anxiety (badge count) 😰

> ℹ️ needs SDK **v4.1.0+** ℹ️

> 🔴 behold 🔴
> the **badge** 🔴
> that tiny red circle 🔴
> sitting on your app icon 🔴
> judging you 🔴
> silently saying "you have **3** things to deal with" 🔴
> has it always been there?? 🔴
> how long?? 🔴
> we can control it 🔴

needs the notification service extension 🔌 + app group 🤝 from [installation](#-installation-the-necessary-evil-)

##### 🧹 autoclearing (the default behavior) 🧹

> 🪄 by default, badge nukes itself to zero when user opens the app 🪄
> ✨ it just *poofs* ✨ like it never existed
> it's very nice actually. very clean. very zen. 🧘
>
> 😤 want to KEEP the badge up? 😤
> 😤 want to maintain the anxiety? 😤
> 😤 bold but fine. add this to `Info.plist`: 😤

```xml
<key>klaviyo_badge_autoclearing</key>
<false/>   <!-- 🔴 you want the red circle to stay. understood. no judgment. -->
```

```xml
<key>klaviyo_badge_autoclearing</key>
<true/>    <!-- 🧹 gone on open. fresh start. clear skies. recommended. -->
```

##### 🎛️ controlling it yourself 🎛️

> 🛑 if you have OTHER notification sources beyond klaviyo 🛑
> 🛑 do NOT set badge count using `UNUserNotificationCenter` or `UIApplication` directly 🛑
> 🛑 they don't know about klaviyo's count 🛑 things will get out of sync 🛑 chaos ensues 🛑
> use THIS instead 👇 it syncs everything 🤝:

```swift
KlaviyoSDK().setBadgeCount(5)
// ☝️ sets badge to 5 🔴
// ☝️ syncs with klaviyo's persisted count 🔄
// ☝️ everyone is happy 😊
// ☝️ the number is correct 🔢
// ☝️ the anxiety is calibrated 😌
```

#### 🫥 sneaky ghost boop (silent push) 🫥

> 👻 silent push 👻
> a notification that makes NO SOUND 🔇
> shows NO ALERT 🫥
> the user has NO IDEA 🙈
> but your app WAKES UP in the background 🌅
> does its little tasks 🐝
> and goes back to sleep 😴
> like a ghost doing maintenance work 👻🔧

> ℹ️ we don't handle silent push ourselves ℹ️ this is apple's domain 🍎
> see [apple's docs on background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app#Enable-the-remote-notifications-capability) 📖

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    // 🎁 klaviyo can include custom key-value pairs
    if let kvPairs = userInfo["key_value_pairs"] as? [String: String] {
        for (key, value) in kvPairs {
            print("🗝️ received: \(key) → \(value)")
            // do something useful here 🔧
            // unlike blob jr. who would probably just stare at it 👁️👁️
        }
        completionHandler(.newData)  // ✅ we got something
    } else {
        completionHandler(.noData)   // 🤷 nothing for us here
    }
}
```

> 🖥️ **VERY IMPORTANT** 🖥️
> silent push **does not work on the iOS simulator** 🚫
> it requires a real physical phone 📱
> a tangible object 📱
> that exists in physical space 📱
> you cannot unit test your way out of this 📱

#### 🎁 there's more inside (custom data) 🎁

> 📦 every klaviyo push — silent OR visible — can carry **custom key-value pairs** 📦
> little bonus payloads 🎁 secret messages 🤫 extra context 📋
> access them via `userInfo["key_value_pairs"]` 🗝️
>
> for 🔔 **standard pushes**: see the [`NotificationService.swift` example](Examples/KlaviyoSwiftExamples/SPMExample/NotificationServiceExtension/NotificationService.swift)
> for 🤫 **silent pushes**: see the code block right above this ☝️

use cases that are NOT exhaustive 💡:
```
🔧 trigger background data sync
📊 log additional analytics context
🎨 update app content or theme dynamically
🧭 route the user to a specific screen on next open
🤯 literally whatever you can dream up we just pass you the dict
```

---

## 💅 pop-ups but make them slay (in-app forms) 💅

> ℹ️ needs SDK **v4.2.0+** ℹ️

> 🎭 picture this 🎭
> your user is scrolling through your app 📱
> having a great time 🌈
> and then suddenly 📋
> a form appears 📋
> beautiful 💅 targeted 🎯 perfectly timed ⏱️
> "hi!! sign up for our newsletter!! 💌"
> they click yes
> you win 🏆
>
> 🖥️ build them in the **Sign-Up Forms** tab in Klaviyo 🖥️
> ✅ the SDK handles display timing 🕐 delivery analytics 📊 engagement tracking 📈 automatically
> ✅ you just call one method
> ✅ genuinely that's it

> 🆕 **v5.0.0+ unlocked**: 🎯 **audience targeting** 🎯
> configure forms in Klaviyo to only show to specific lists 📋 or segments 🎭
> based on profile data set via `KlaviyoSDK().set(...)` 🪪
> forms for logged-in users only? ✅ for premium subscribers only? ✅ for people named Blob Jr.? ✅

### ✅ checklist before we begin ✅

```
☑️  SDK version 4.2.0 or higher (latest is best 🏆 we keep improving things 🏗️)
☑️  KlaviyoSwift 🐦 imported in your target
☑️  KlaviyoForms 📋 imported in your target (yes BOTH. they're a duo. 🎭)
☑️  read the migration guide if you're coming from 4.2.0–4.2.1 📖 things changed
```

#### 📊 feature availability by version 📊

| 🎁 feature | 📦 minimum version |
|---|---|
| basic in-app forms 📋 | v4.2.0 |
| ⏱️ time delay (show form after N seconds) | v5.0.0 |
| 🎯 audience targeting (lists/segments) | v5.0.0 |

### ⚙️ turning it on ⚙️

```swift
import KlaviyoSwift   // 🐦 (you already have this)
import KlaviyoForms   // 📋 (you need this one too. don't forget it. we mean it.)

// ✨ option A: chain it right onto initialize (satisfying 🔗):
KlaviyoSDK()
    .initialize(with: "YOUR_KLAVIYO_PUBLIC_API_KEY")  // 🚀 step one
    .registerForInAppForms()                           // 📋 step two. done. wow.

// ✨ option B: call it separately, somewhere later in your app:
KlaviyoSDK().registerForInAppForms()  // 📋 works anywhere after init. flexible king. 👑
```

> 🔄 **zero re-registration needed** 🔄
> forms auto-respond to API key changes and profile changes
> you register once 1️⃣ and walk away 🚶

#### ⏱️ session timeout (advanced cozy config) ⏱️

> 🧠 a **session** = one continuous run of the user engaging with your app 🧠
> users won't see the same form more than once per session 🙅 (sensible. merciful. 🙏)
> sessions time out after a period of inactivity ⏸️
>
> 🕐 **default timeout**: 3600 seconds (one entire hour ⏰)
> ✏️ want to change it? bring your own `InAppFormsConfig`:

```swift
import KlaviyoForms  // 📋

// ⏱️ example: 30-minute timeout (cozy ☕):
let config = InAppFormsConfig(sessionTimeoutDuration: 1800)  // 1800s = 30 minutes
KlaviyoSDK().registerForInAppForms(configuration: config)

// ⏱️ example: 1-second timeout (CHAOS mode 🌪️ — for testing only PLEASE):
let chaosConfig = InAppFormsConfig(sessionTimeoutDuration: 1)
// every single app open will be treated as a new session
// every single app open could trigger a form
// do not ship this to production
// i'm looking at you 👀
```

### 🚪 turning it off (when you need to) 🚪

> 👋 user logs out? 🚪 sensitive screen? 🙈 just done with forms for now? 🏖️

```swift
import KlaviyoForms  // 📋

KlaviyoSDK().unregisterFromInAppForms()
// ✅ webview: destroyed 💥
// ✅ subscriptions: cancelled 🚫
// ✅ state: cleared 🧹
// ✅ next registerForInAppForms() call = fresh new session 🆕
```

### 🔗 forms can also deep link 🔗

> yep 🔗 forms support deep links too 🔗
> same setup as push deep links 👆
> [see step 3 of the URL schemes section above](#%EF%B8%8F%EF%B8%8F%EF%B8%8F-path-one-url-schemes-old-faithful-%EF%B8%8F)
> [apple also has opinions](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)) 🍎

---

## 🔬 nerd corner 🔬

> 🤓 congratulations on making it this far 🤓
> you have earned access to the technical details 🏅
> please collect your prize: knowledge 📚

### 🏖️ the simulation (sandbox) 🏖️

> ℹ️ needs SDK **v2.2.0+** ℹ️

> 🍎 apple runs **two parallel push universes** 🍎:
>
> 🏭 **PRODUCTION** — real users. real app store. real consequences. if something breaks, real people don't get their push notifications. scary. 😰
>
> 🏖️ **SANDBOX** — dev certificates. fake world. safe to break things. no actual users affected. it's like a push notification snow globe. 🌨️

our SDK **automatically figures out which universe your token belongs to** 🤖
stores it 💾 communicates it to our backend 📡 routes everything correctly 🗺️
**you do absolutely nothing extra** 🪄
deploy to sandbox → sdk sees the dev cert → sends tokens to sandbox → works ✅
it's like magic except it's boring certificate parsing 🧾 which is also kind of magic if you think about it 🪄

### 🚿 the flush (data transfer) 🚿

> 🫙 starting in **v1.7.0**: the SDK doesn't fire API calls immediately 🫙
> instead it **caches** events and profiles locally 📥
> then **flushes** them in batches on a timer ⏱️
> the timer speed depends on your connection 📡:

| 📡 network type | ⏱️ flush interval | vibe |
|---|---|---|
| 🛜 WiFi / WWAN | 10 seconds | ⚡ zappy |
| 📶 Cellular | 30 seconds | 🐢 patient |

> 📴 no signal at all? 📴
> the cache just… holds on 🫙
> like a little backpack of unsent data 🎒
> waiting patiently 🙏
> the second the connection returns 🌅
> *WHOOOOSH* 🚿 it all goes out
> nothing is lost 💪 no data left behind 🫡

### 🔁 try again bestie (retries) 🔁

> 🌐 the internet is a lawless place 🌐
> requests fail 💀 timeouts happen ⏱️ APIs rate-limit you 🚫
> the SDK handles all of this without you having to think about it:

```
🕐 network timeout    →  chill, retry on next flush interval
429 rate limit        →  exponential backoff with jitter 🎲
                          (waits longer each time 📈)
                          (adds randomness to avoid thundering herd 🐘🐘🐘)
                          (keeps us from getting banned from our own API 😅)
```

### ⚖️ the legal blorbo (license) ⚖️

KlaviyoSwift is available under the **MIT license** 📜
see the `LICENSE` file for the full blorbo 🧑‍⚖️
tldr: use it, ship it, just don't claim you wrote it 🙃

---

## 🆘 help me 🆘

> 🛠️ want to contribute? 🛠️
> we welcome PRs 🤝 feedback 💬 bug reports 🐛 and kind words 💌
> see [CONTRIBUTING.md](.github/CONTRIBUTING.md) 📖
> open an [issue](https://github.com/klaviyo/klaviyo-swift-sdk/issues) 🐛
> we read them. we respond. we are human(s). 🧑‍💻

---

<div align="center">

---

## 🍝🍝🍝 fin 🍝🍝🍝

*🌈 built with approximately 700 emojis, one legal section, and several blob jr. appearances 🌈*

*📊 if you've integrated the SDK successfully: congratulations 🏆 you are incredible 🌟*
*😔 if you're still stuck: open an issue 🐛 blob jr. would want you to ask for help 😔🫂*

😂📱🔔📊🪪👤📧📞🛒💳🚀🔄🔗🖼️😰🫥🎁💅⏱️🏖️🚿🔁⚖️🆘🍝

> *please hydrate 💧*
> *tell blob jr. we said hi 🫧*

---

</div>
