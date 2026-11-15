# LinkMeter

Shows connection type, signal, and download/upload speed on one screen, with a Wi-Fi / Cellular selector.
The speed test is pinned to the selected interface, so you can test cellular while Wi-Fi is on.

## What iOS does and doesn't expose

- Band number (B13, n77), dBm, and negotiated link rate are not available to normal apps.
- The pill shows the cellular generation (5G, 5G NSA, LTE, 3G) or the Wi-Fi network name.
- Signal: real Wi-Fi strength (0-100%) only if the app has the Wi-Fi Info entitlement and Location permission.
  Otherwise it's a quality rating estimated from the last speed test (speed and latency).
- Speeds: measured against speed.cloudflare.com, 8 seconds per direction (up to about 80 MB down, 40 MB up).

### Enabling real Wi-Fi strength (optional)
Add `Resources/LinkMeter.entitlements` with `com.apple.developer.networking.wifi-info` = true,
and `CODE_SIGN_ENTITLEMENTS: Resources/LinkMeter.entitlements` to the target settings. Needs a paid developer account
and may make AltServer sideloading fail if the capability isn't provisioned.

## Build

Option A (Mac): `xcodegen generate`, open `LinkMeter.xcodeproj`, run.

Option B (no Mac): push to GitHub, the `Build iOS (unsigned IPA)` workflow produces `LinkMeter-unsigned-ipa`.
Sideload with AltServer using your Apple ID.
