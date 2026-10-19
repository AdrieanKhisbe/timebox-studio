# Timebox Studio

For saved devices, logical names and selection rules, see
[device configuration](docs/device-configuration.md).
For structured results and exit codes, see [CLI output](docs/cli-output.md).
For live device alarm enumeration, see [alarm listing](docs/alarms.md).

Control a Divoom **Timebox Evo** (16×16 RGB LED display) directly from **macOS and iOS** —
send arbitrary images, solid colors, and brightness — with **no Divoom app, no Node, no
Electron/web server, and no ESP32/Raspberry Pi** in the control path. Pure Swift over
Apple's native Bluetooth stack.

It is primarily a **Swift library** (`TimeboxClient`) you can build apps on top of,
plus a command-line tool (`timeboxctl`) and a minimal SwiftUI shell.

## How it works (short version)

The same image/command encoding drives two transports, selected automatically per platform:

- **macOS → Bluetooth Classic SPP/RFCOMM** (`IOBluetooth`). The Evo's LED protocol runs
  over Classic SPP; the wire format and image encoding were reverse-engineered from the
  official Divoom Android app.
- **iOS → BLE** (`CoreBluetooth`). The device's BLE "Transparent UART" endpoint *is*
  usable — the trick is the JieLi **RCSP** wrapper (`FE EF AA 55 | LEN | payload | sum16`)
  and tunneling the **same SPP command bytes** through the device's reliable `01` command
  channel (`01 <seq> 00 00 00 <SPP command>`). Reverse-engineered from a BLE capture of
  the official iOS app.

`TimeboxClient` exposes one API (`connect` / `setBrightness` / `setColor` / `send(image:)`)
over both. See [`DEVELOPMENT_NOTES.md`](DEVELOPMENT_NOTES.md) for the protocol details.

## Requirements

- macOS (Apple Silicon or Intel), Swift 5.9+
- A Divoom Timebox Evo **paired** with your Mac in **System Settings → Bluetooth**
  (one-time, manual — it shows up as e.g. `Timebox-Evo-audio`). Pairing is the only
  step that can't be automated.

## Build & test

```sh
swift build
swift test
```

## Use the CLI

List paired devices to find your Timebox's address:

```sh
.build/debug/timeboxctl list
.build/debug/timeboxctl list --all   # include other paired Bluetooth devices
```

Send an image / color / brightness (the RFCOMM channel is auto-resolved from the
device's SDP — no need to specify one):

```sh
.build/debug/timeboxctl image art.png   --address <MAC>
.build/debug/timeboxctl color FF0000     --address <MAC>
.build/debug/timeboxctl brightness 40    --address <MAC>
```

Interactive mode — one persistent connection, stream commands:

```sh
.build/debug/timeboxctl repl --address <MAC>
# then type:  image art.png  |  color 00FF00  |  brightness 25  |  quit
```

> If a command times out connecting to the SPP channel, macOS is probably holding it
> for the paired speaker — **power-cycle the Timebox** and retry.

## Use as a library

Add this package as a SwiftPM dependency and import `TimeboxBluetooth` (+ `TimeboxKit`):

```swift
import TimeboxBluetooth
import TimeboxKit

let client = TimeboxClient()

// Find the user's Timebox among paired Bluetooth devices:
guard let timebox = TimeboxClient.discoverTimeboxes().first else {
    print("No paired Timebox found — pair it in System Settings → Bluetooth first.")
    return
}

try await client.connect(to: timebox)         // SPP channel auto-resolved from SDP
try await client.send(imageAt: "art.png")      // any PNG/JPG/BMP/GIF -> 16×16
try await client.setColor(PixelRGB(red: 255, green: 0, blue: 0))
try await client.setBrightness(60)
client.disconnect()
```

Call the async methods from a context with a running run loop (any AppKit/SwiftUI app).
The connection is **persistent** — connect once, then push images/colors at any time.

### On iOS

Same `TimeboxClient`, same `send`/`setColor`/`setBrightness` — only connection differs.
There is no manual pairing or SDP step; CoreBluetooth finds the device by name (or
attaches if iOS already holds it connected as a speaker):

```swift
let client = TimeboxClient()
try await client.connect()        // iOS-only convenience: scans BLE for the Timebox
try await client.setBrightness(80)
try await client.send(image: frame)
```

Add `NSBluetoothAlwaysUsageDescription` to the app's Info.plist. The transport is
`CoreBluetoothRCSPTransport` (RCSP over BLE); it is chosen automatically on iOS.

### Finding the device ("will this work with anyone's Timebox?")

Addresses and channels are resolved per device:

- `TimeboxClient.discoverTimeboxes()` — paired devices whose name contains "Timebox".
- `TimeboxClient.pairedDevices()` — *all* paired devices, so you can present your own picker.
- The Bluetooth **address** comes from discovery; the **RFCOMM channel** is resolved per
  device from its SDP (Serial Port Profile, UUID `0x1101`), exactly like the official app.

The CLI and library both include audio-named Timeboxes. An explicit `--address`
selects one device; `TIMEBOX_ADDRESS` is the environment fallback, followed by a
saved default when provided by configuration, then the sole discovered Timebox.
Ambiguous discovery fails instead of selecting an arbitrary device. Model/firmware behavior must
be verified on the target Evo; pairing or opening an RFCOMM channel alone does
not establish display compatibility. See the
[Classic baseline validation record](docs/validation/evo-classic-baseline.md).

## Library products

- **`TimeboxKit`** — protocol encoding (`TimeboxPacketEncoder`, `TimeboxImageEncoder`),
  `PixelFrame`/`PixelRGB`, and `ImageToPixelFrameConverter` (PNG/JPG → 16×16, CoreGraphics).
- **`TimeboxBluetooth`** — `TimeboxClient` (high-level API), `IOBluetoothTimeboxTransport`
  (macOS Classic SPP), `CoreBluetoothRCSPTransport` (iOS/macOS BLE via RCSP), and
  paired-device discovery.

## Project layout

```text
TimeboxStudio/
  TimeboxKit/        protocol encoding + image conversion (platform-light)
  Bluetooth/         TimeboxClient, IOBluetooth SPP transport, discovery, diagnostics
  Persistence/       SavedDesign / DesignStore
  Utilities/         hex parsing, logging
  App/ UI/           minimal SwiftUI shell
timeboxctl/          command-line tool
TimeboxStudioTests/  packet + image encoding tests
```

## Status

- ✅ Images, solid color, brightness — working on real hardware, **macOS (Classic SPP)
  and iOS (BLE/RCSP)**.
- ⬜ Not yet: GIF/animation, a full pixel-editor GUI (the SwiftUI shell is minimal),
  saved-design persistence wired into the UI.

## Constraints honored

Native macOS Swift only; no Divoom app, Node, Electron/web, or ESP32/Pi in the control
path; protocol encoding kept separate from transport; a raw-hex escape hatch is retained.

### Evo display channels

```sh
timeboxctl display clock --style 0 --device desk
timeboxctl display light --color FF0000 --brightness 50 --device desk
timeboxctl display design --device desk
timeboxctl display clock --device desk  # restore stored clock profile
timeboxctl design 1 --device desk       # requires fresh three-tab capability
```

Equivalent REPL commands and `TimeboxClient.display(_:)` use the same typed
encoder. Explicit clock styles apply a complete white/time-only profile; explicit
light options apply a complete plain-light profile (missing color white, missing
brightness 100, power on). They do not preserve unspecified stored settings.
Clock styles0–5 were visually confirmed. Bare clock/light selection reads fresh
settings and re-encodes the stored target profile; unknown layouts fail before
control writes. Design tabs0–2 require a fresh positive device capability reply.
All three tabs showed distinct existing artwork on the tested Evo; legacy VJ
effects remain unverified. REPL/client live
operations reconnect on success and remain disconnected on failure. Custom/design
channel selection is distinct from stored-content enumeration. See [display evidence and acceptance](docs/validation/evo-display-channels.md).

### Original Timebox Mini and model selection

The CLI supports original Mini brightness, solid color, static11×11 images, clock display and synchronization, native stopwatch, three-slot alarms, native GIF uploads, streamed text, and live status:

```sh
timeboxctl image art.png --address AA:BB:CC:DD:EE:FF --model mini --channel 4
timeboxctl repl --device mini --model mini --channel 4
timeboxctl display clock --device mini --model mini
timeboxctl time sync --device mini --model mini
timeboxctl stopwatch start --device mini --model mini
timeboxctl alarm list --device mini --model mini --json
timeboxctl status --device mini --model mini --json
timeboxctl animation art.gif --device mini --model mini [--adapt]
timeboxctl text "Hello Mini" --stream --device mini --model mini
```

Use `--model evo` for Evo, or save `model: evo` / `model: mini` in that device's
config entry. CLI `--model auto` bypasses the saved override. Reliable automatic
hardware identification has not been established, so an unknown model fails
before display writes and asks for an explicit choice. Bluetooth names and RFCOMM
channels alone are not identity evidence. REPL target changes resolve the new
model independently; startup overrides do not carry across targets.

`TimeboxClient(model: .mini)` enables the library Mini profile. Existing
`TimeboxClient()` callers retain Evo behavior; pass `model: nil` to request
conservative automatic identification. Mini BLE/iOS, native countdown and stored
content remain unverified and unsupported. Mini GIF uploads use a conservative
12-frame/common-delay policy; see [format and physical validation](docs/validation/mini-animation.md).
Native clock, stopwatch and alarm
evidence is recorded in the [production validation report](docs/validation/mini-clock-stopwatch-alarms.md). See the [integration and validation
report](docs/validation/timebox-mini.md) for protocol sources, image conversion,
detection limitations and pending hardware acceptance.
Clock synchronization uses one local Gregorian snapshot and reports transmission;
see [Mini clock-sync evidence](docs/validation/mini-clock-sync.md) for its manual
acceptance and protocol sources.
Mini scrolling text requires explicit `--stream`, which holds the Mac connection
for one full scroll; see [streaming behavior and validation](docs/validation/mini-streaming-text.md).
