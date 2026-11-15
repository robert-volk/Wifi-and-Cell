# LinkMeter

Shows connection type, signal, and download/upload speed on one screen, with a Wi-Fi / Cellular selector.
The speed test is pinned to the selected interface, so you can test cellular while Wi-Fi is on.

## What it does

Live monitor, no manual tests. While the app is open it:
- polls Wi-Fi strength every second (Wi-Fi needs the Wi-Fi Info entitlement and Location permission),
- runs short repeating test bursts on the selected link for link down/up and latency,
- charts live traffic from the interface byte counters.
Pause/Play (top right) stops everything. It also pauses when the app is backgrounded.

## What iOS doesn't expose

- Band (2.4/5/6 GHz): not readable. Set it yourself from the Band menu. Without it, a hint appears if speeds exceed 200 Mbps.
- dBm: iOS gives a 0-1 strength. dBm shown is a rough scaling (about -100 to -40). Without the entitlement, signal is a quality estimate.
- Router link rate: not available. "Link" speed is measured to speed.cloudflare.com.
- Cellular band and dBm: not available.

The workflow ad-hoc signs the app with `Resources/LinkMeter.entitlements` so AltServer can request the Wi-Fi capability.
If AltServer install fails, delete the "Ad-hoc sign" step in the workflow.

## Build

Option A (Mac): `xcodegen generate`, open `LinkMeter.xcodeproj`, run.

Option B (no Mac): push to GitHub, the `Build iOS (unsigned IPA)` workflow produces `LinkMeter-unsigned-ipa`.
Sideload with AltServer using your Apple ID.
