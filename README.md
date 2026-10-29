# SmartPlane Pro · Revival for iOS

[![Build iOS IPA](https://github.com/Robin9094707/SmartPlane-Pro-chatGPT/actions/workflows/ios-ipa.yml/badge.svg)](https://github.com/Robin9094707/SmartPlane-Pro-chatGPT/actions/workflows/ios-ipa.yml)

A native SwiftUI cockpit and Bluetooth research tool for bringing TobyRich
planes back to modern iPhones. **Version 1.0.0 — Research Preview.**

> **SmartPlane Pro flight compatibility is not yet confirmed.** The public
> TobyRich code documents the older SmartPlane/Moskito SmartLink protocol.
> This app implements that protocol and diagnoses unknown Pro firmware without
> guessing motor, flight-mode or stunt commands. It is not yet a complete Pro
> replacement. No real aircraft was available for testing.

## Included

- Native CoreBluetooth scanning, connect/cancel/disconnect, RSSI, battery data.
- SwiftUI interface with native Liquid Glass on iOS 26+, material fallback on 18+.
- Portrait/landscape cockpit, momentary throttle, self-centering rudder joystick,
  tilt steering, neutral calibration, reversed steering and adjustable thrust cap.
- Explicit arm gate, STOP, background/interruption stop attempt, no auto-rearming.
- Separate offline training mode which sends **no Bluetooth commands**.
- GATT inspector: all discoverable services and characteristics, flags, reads,
  descriptors, notifications and individually confirmed raw hexadecimal writes.
- Timestamped JSON diagnostics with advertisements, values and bounded event log.
- Firmware/model/manufacturer versions **when exposed by the device**, not a full
  firmware dump. iOS peripheral identifiers, not Bluetooth MAC addresses.
- Validated, persistent JSON profiles for known packet layouts. See the
  [example](docs/control-profile-example.json); complex Pro handshakes or checksums
  will need a dedicated driver once recovered.
- GitHub Actions: protocol tests, simulator compilation, training UI smoke test,
  native portrait/landscape screenshots, device archive, unsigned
  IPA, source ZIP, hashes and build logs.

## Download and first test

[Open IPA builds](https://github.com/Robin9094707/SmartPlane-Pro-chatGPT/actions/workflows/ios-ipa.yml).
Select a green run → Artifacts → `SmartPlanePro-1.0.0-unsigned-IPA`.
Sign the included `.ipa` using your own Apple profile or existing signing service.
No signing secrets are required for CI.

[Deutsche Anleitung](docs/INSTALL-DE.md) · [Protocol evidence and limitations](docs/PROTOCOL-RESEARCH.md)

First try **Hangar → Cockpit im Trainingsmodus ansehen**. For real hardware,
remove the propeller, scan and connect, then export a Bluetooth-Labor report.
A matching UUID does not establish correct Pro behavior. Confirm the protocol and
perform bench tests before flight. STOP requests zero output; delivery and actual
motor shutdown cannot be guaranteed after link loss.

## Build locally (Mac)

Requires Xcode 26 or newer and XcodeGen; app deployment target iOS 18.

```sh
brew install xcodegen
xcodegen generate
open SmartPlane.xcodeproj
```

For a signed device build, enable signing in the generated target and choose your
own team. The checked-in CI builds unsigned. A Mac is not needed to trigger the
GitHub build.

```sh
cd ProtocolCore
swift test
```

## Layout

`SmartPlane/Bluetooth` owns BLE lifecycle, GATT discovery, flow control, event
logging and reports. `SmartPlane/Views` contains the hangar, scanner, cockpit and
laboratory. `ProtocolCore` is a dependency-free Swift package for wire formats,
validation and arming interlocks. `project.yml` generates the Xcode project.

## Research still needed for SmartPlane Pro

The old Pro Android package is `com.tobyrich.app.Vegas`. Public download listings
were located, but the APK could not be downloaded in this development session.
There has been no Pro APK decompilation or verified reconstruction of its packet
format. Original-app captures or a legitimate APK plus the user's GATT report
are the next evidence needed. Pro stunts, helicopter/airplane switching and DFU
are intentionally absent until their exact protocol is established.

## License

New implementation: MIT. Protocol references and TobyRich notices: [NOTICE](NOTICE).
This project is unofficial and is not affiliated with TobyRich.
