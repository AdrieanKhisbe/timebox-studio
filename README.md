# Timebox Studio

For saved devices, logical names and selection rules, see
[device configuration](docs/device-configuration.md).
For structured results and exit codes, see [CLI output](docs/cli-output.md).

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

Tests require the full Xcode installation (for XCTest), with its license accepted
and initial setup completed. If `xcode-select -p` points to Command Line Tools,
select Xcode with `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`,
or prefix the commands below with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
swift build
swift test
```

## Continuous integration and delivery

[GitHub Actions](https://github.com/AdrieanKhisbe/timebox-studio/actions/workflows/ci.yml)
runs on every push, pull requests to `main`, and manual dispatches. It builds all
products, runs the unit tests, and builds release executables on both Apple Silicon
and Intel macOS runners. A separate job compiles `TimeboxBluetooth` and its
dependencies for iOS without signing.

Each successful macOS job delivers a `timebox-studio-macos-arm64` or
`timebox-studio-macos-x86_64` artifact, retained for 14 days. Download the matching
artifact from the workflow run, unzip it, then extract its `.tar.gz` archive. It
contains `timeboxctl`, the standalone `TimeboxStudio` executable, and documentation.
These are unsigned developer builds; the SwiftUI executable is not an `.app` bundle.
The workflow does not publish GitHub Releases or deploy to the App Store.

The tests cover hex parsing, pixel-frame validation, packet checksums, and image
palette encoding. Bluetooth connection and display behavior require a real Timebox
and are checked manually.

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

## Interactive REPL

Requires Swift 6 or newer to build. The package retains Swift 5 language mode.
The macOS CLI uses Bestline automatically in supported terminals, with completion,
editing and searchable session history. Pipes use plain input without ANSI prompts.
Use `repl --editor plain` for the plain terminal reader. Set `NO_COLOR` to suppress
the bold blue `timebox` and bold red `>` prompt. History stays in memory unless
`repl --history-file PATH` is supplied.

```sh
.build/debug/timeboxctl repl --address "$MAC"
.build/debug/timeboxctl repl --mock
```
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
Tab2 distinct content and legacy VJ effects remain unverified. REPL/client live
operations reconnect on success and remain disconnected on failure. Custom/design
channel selection is distinct from stored-content enumeration. See [display evidence and acceptance](docs/validation/evo-display-channels.md).
