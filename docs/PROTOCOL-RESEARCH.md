# Protocol research — 29 October 2026

## Result and honest compatibility boundary

The pictured product is TobyRich **SmartPlane Pro**, not the 2013 SmartPlane.
No confirmed Pro control packet format has been recovered in this project yet.
This is a native research-preview controller and BLE inspector, **not a verified
replacement for every feature of the Pro app**. Successful compilation does not
establish hardware compatibility. No hardware was available during development.

## Primary sources inspected

1. TobyRich Android application: https://github.com/TobyRich/app-smartplane-android
   `SmartPlane/src/main/res/raw/services.plist` provides
   service and characteristic UUIDs for older SmartPlane firmware.
   https://github.com/TobyRich/app-smartplane-android/blob/master/SmartPlane/src/main/res/raw/services.plist
2. Official library: https://github.com/TobyRich/lib-smartlink-android
   inspected revision `bf9952ee253b6f35dac2d16c0fd91d61a24d1329`.
   `BLESmartplaneService.java` clamps engine to 0…254, signed rudder to −126…126,
   selects write-without-response, sets both to zero on attach, and skips unchanged
   values. Our implementation is independently written in Swift; see NOTICE.
3. Manufacturer's developer reply in its user community:
   https://smartplane.userecho.com/communities/1-user-community/topics?lang=en&page=2
   The older SmartPlane uses the PowerUp 3.0 protocol with TobyRich's UUID base.
   This is **not evidence for SmartPlane Pro**.
4. SmartPlane Pro manufacturer manual filed for FCC 2AM7J-SPPRO:
   https://fcc.report/FCC-ID/2AM7J-SPPRO/3517152.pdf
   Documents tilt/joystick controls, plane/helicopter modes and stunts, but no BLE
   commands. It describes firmware behavior on disconnect; this project cannot
   independently verify that behavior on the user's firmware.
5. A current hardware-tested community implementation for **Moskito**:
   https://github.com/tim-fan/moskito-controller
   Also examined https://github.com/tanatana/dalmazia
   Both use the older SmartLink channel UUIDs. Neither proves Pro compatibility.

## APK investigation

The former Pro Android app is `com.tobyrich.app.Vegas`, version 1.8.0.
Archived listings exist on APKPure and other sites. Download requests in this
session returned HTTP 403/503; no APK was recovered, decompiled, or executed.
Therefore no claim of Pro reverse engineering from that APK is made. A legitimate
copy of this APK or captures from the original app would permit further protocol
work. Do not redistribute the original manufacturer's binary without permission.

## Implemented older protocol

| Profile | Service | Throttle | Rudder |
|---|---|---|---|
| SmartLink | 75B64E51-F171-4ED1-921A-476090D80BA7 | 75B64E51-0010-4ED1-921A-476090D80BA7 | 75B64E51-0021-4ED1-921A-476090D80BA7 |
| sml1test | 75B64E51-F181-4ED1-921A-476090D80BA7 | 75B64E51-F184-4ED1-921A-476090D80BA7 | 75B64E51-F185-4ED1-921A-476090D80BA7 |

Throttle is one unsigned byte 0…254. Rudder is signed int8 −126…126 in two's
complement. Commands are sent only after explicit arming; unchanged values are
suppressed. Frame requests are coalesced at up to 20 Hz, with CoreBluetooth flow
control and serialized acknowledged writes. No undocumented handshake, launch,
flight-mode, stabilization, or stunt command is guessed.

Matching UUIDs and writable properties identify a compatible transport shape,
not proof of compatible aircraft behavior. Even a recognized profile needs a
propeller-off bench test. Imported profiles have the same limitation.

## BLE diagnostics

* Unfiltered timed BLE discovery: name, iOS peripheral UUID, RSSI, manufacturer
  bytes, advertised service UUIDs, service data and other exposed metadata.
* All discoverable GATT services/characteristics, read/write/notify/indicate flags.
* Automatically read standard Device Information / Battery characteristics.
* On request, read all readable characteristics, inspect readable descriptors,
  subscribe/unsubscribe to notifications, or send a confirmed raw hex command.
* Export structured JSON with timestamps, last values and a bounded event log.
* No MAC address is exposed by CoreBluetooth. A GATT list is not a firmware dump.
  Firmware versions require the peripheral to publish them; full flash reads need
  a documented vendor bootloader/debug interface, which has not been established.
* No DFU writes, bootloader entry, firmware extraction or flashing are performed.

## Completing Pro support

1. Remove the propeller; connect and export a baseline report.
2. Read all readable characteristics, subscribe to relevant notification channels,
   export another report. Do not brute-force write commands.
3. Compare Pro service UUIDs against the published older protocol.
4. Obtain a legitimate original Pro APK or original-app Bluetooth HCI capture.
5. Recover initialization, control packet layout, checksums, mode/stunt opcodes,
   telemetry parsers and failsafe timing. Add evidence-linked fixtures and tests.
6. Add a dedicated Pro driver if authentication, stateful handshakes, multi-byte
   channels or checksums are required. JSON profiles presently support static bytes
   and single-byte throttle/rudder substitutions only; they are not universal.
7. Verify zero, rudder direction, throttle limits, write scheduling, interruption
   stop and real disconnect behavior on a restrained, propeller-off aircraft.
8. Only then perform a short, controlled outdoor flight test.

## Build validation

GitHub Actions runs Swift unit tests, compiles an iOS Simulator build and archives
an arm64 device app using the runner's Xcode 26 SDK. Check the actual Actions run
for results. No hardware tests have been performed. Bluetooth control needs a
physical iPhone; the Simulator cannot verify this aircraft's BLE behavior.
