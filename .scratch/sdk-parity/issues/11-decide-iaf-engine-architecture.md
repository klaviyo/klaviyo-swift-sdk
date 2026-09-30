# 11 — Decide: where In-App Forms trigger evaluation and rendering live
Type: prototype
Status: open
Blocked by: 01, 03

## Question

Today a hidden, never-throttled `WKWebView` runs the onsite `klaviyo.js` engine for the whole app
session; it evaluates targeting in JS and is later *presented* as the form. Competitors (per 01)
evaluate triggers natively from downloaded definitions and create a webview only at display time,
with assets prefetched. Using 03's memory/latency numbers, decide between: (A) status quo + lazy
tricks (create the webview on first eligible event? — only possible if eligibility is known
natively); (B) headless engine in `JavaScriptCore` (`JSContext`, no WebContent process) running a
DOM-less build of the onsite engine, plus an on-demand `WKWebView` renderer fed prefetched form HTML;
(C) native trigger evaluation from a forms-definition endpoint (does one exist? see 02) with
webview-only-at-display. Each option's cost falls partly on the onsite/forms team — they must be in
the session. Prototype: a `JSContext` spike that loads klaviyo.js in-app mode and reports which
browser APIs it touches (feasibility of B), and a memory comparison of "webview alive" vs "webview on
demand". Output: IAF architecture ADR + the contract the SDK needs from onsite.
