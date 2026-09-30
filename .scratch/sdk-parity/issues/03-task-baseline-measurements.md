# 03 — Task (HITL): measure the SDK before arguing about it
Type: task
Status: open
Blocked by: —

## Question

Produce the numbers the perf tickets (07, 11, 14) are gated on, on a physical device with a release
build of the example app, and attach them to this ticket. The agent cannot run Xcode from this
environment, so this is a checklist for a human on the mobile team (≈ half a day):

1. **Main-thread cost of tracking**: Instruments → Time Profiler while calling
   `KlaviyoSDK().create(event:)` 200× in a loop with a 10-property payload (a) with an empty queue,
   (b) with 150 queued requests. Record main-thread ms total and per call; note time in
   `KlaviyoReducer.reduce`, `Equatable` compares (`removeDuplicates`), `AnyCodable` init.
2. **Persistence cost**: same run, File Activity instrument → size of
   `Library/klaviyo-<key>-state.json` at queue = 150, number of full-file rewrites during the run.
3. **Init to first flush**: os_signpost or logs from `initialize(with:)` to the first 2xx, cold launch,
   Wi-Fi; also time-to-`.completeInitialization`.
4. **Network**: bytes on the wire for 100 events sent one-per-request (Charles/Proxyman or
   `URLSessionTaskMetrics`): total request bytes, header share, number of TCP/TLS handshakes.
5. **IAF memory**: Xcode memory gauge / `vmmap` — app footprint and the WebContent process footprint
   with `registerForInAppForms()` called and no form displayed, at 1 min and 10 min; time from
   registration to `handShook` on Wi-Fi and on simulated 3G (Network Link Conditioner); bytes fetched
   by the webview per cold session (klaviyo.js, fonts CSS, forms data).
6. **Binary size**: `KlaviyoSwift`, `KlaviyoCore`, `KlaviyoForms` contribution to the app's
   compressed IPA (App Thinning report) for a release build.

Answer = the table of numbers + device/OS/SDK version. No decisions here.
