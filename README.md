# LinkMeter

Wi-Fi only. Shows the Wi-Fi band and a continuously updated Wi-Fi link speed (down and up), plus latency to the router.

## Real Wi-Fi speed (recommended)

1. On a PC wired to the router, run `Server/run_server.bat` (or `python Server/lan_speed_server.py`). Allow it on Private networks if Windows asks.
2. It prints the PC's address. Enter it in the app under "PC address" and tap Done.
3. The app now downloads from and uploads to the PC over Wi-Fi only, so the number is the Wi-Fi link, not your internet.

With no PC address set, speed is measured to the internet (speed.cloudflare.com), about 80 MB a minute.

## Router latency

Time for the router to answer a connection on port 80 (opened or refused both count). The router address is the PC's address
with the last number set to 1, unless you type one.

## Band

iOS doesn't let apps read the band (2.4, 5, 6 GHz) or the router's negotiated link rate. Choose the band from the menu.
If you haven't, a hint shows when speeds exceed 200 Mbps.

## Build

Option A (Mac): `xcodegen generate`, open `LinkMeter.xcodeproj`, run.

Option B (no Mac): push to GitHub, the `iOS Build (unsigned IPA)` workflow produces `LinkMeter-unsigned-ipa`.
Sideload with AltServer using your Apple ID.
