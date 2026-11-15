# LinkMeter

Wi-Fi only. Shows the Wi-Fi band and a continuously updated link speed (down and up).

- Link speed: short repeating test bursts over Wi-Fi (about 80 MB a minute) against speed.cloudflare.com.
  Pause/Play stops it. It also pauses when the app is backgrounded.
- Band: iOS doesn't let apps read the band (2.4, 5, 6 GHz) or the router's negotiated link rate.
  Choose the band from the menu. If you haven't, a hint shows when speeds exceed 200 Mbps.

## Build

Option A (Mac): `xcodegen generate`, open `LinkMeter.xcodeproj`, run.

Option B (no Mac): push to GitHub, the `iOS Build (unsigned IPA)` workflow produces `LinkMeter-unsigned-ipa`.
Sideload with AltServer using your Apple ID.
