# Original Timebox Mini integration

Issue: [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20).
Investigation and implementation date: 2026-10-19.

## Supported interface

The original Mini uses 11×11 pixels, high-four-bit RGB444 quantization and escaped
interior bytes. Evo retains its 16×16 palette encoding and unescaped framing.
Brightness, solid color, static files, clock display and synchronization, native stopwatch and
three-slot alarms are integrated into the ordinary CLI, REPL and `TimeboxClient`.
Native GIF upload is also supported; see [animation limits and validation](mini-animation.md).
See [clock/stopwatch/alarm validation](mini-clock-stopwatch-alarms.md) for the later
promotion and exact hardware scope. Raw packets remain an escape hatch. Other
channels except clock/light, native countdown, MiniToo and
Mini BLE/iOS have no compatibility claim. Mini library connections on iOS fail
before BLE connection.

Clock synchronization is described separately in the
[Mini clock-sync report](mini-clock-sync.md).
Scrolling text requires explicit [host streaming](mini-streaming-text.md), which
keeps the Mac connected for one complete scroll. Remaining countdown and automatic
identity evidence is recorded in [the capability follow-up](mini-remaining-capabilities.md).
Model-aware [live status](mini-status.md) reports fresh configured mode and
brightness using the Mini-specific settings layout.
Mini [light selection](mini-light.md) also supports a preserved stored profile
or an explicit full plain-light profile.

```sh
timeboxctl color FF0000 --address "$MAC" --model mini --channel 4
timeboxctl brightness 25 --address "$MAC" --model mini --channel 4
timeboxctl image picture.png --address "$MAC" --model mini --channel 4
timeboxctl repl --address "$MAC" --model mini --channel 4
```

`--model auto|evo|mini` defaults to automatic resolution in the CLI. Precedence is
explicit non-auto selection, saved override, then verified identification.
Explicit `--model auto` bypasses the saved override. Configuration may contain:

```yaml
default: mini
devices:
  mini:
    mac: "$MAC"
    bluetooth_name: AKTBR
    model: mini
```

Use a real MAC in this illustrative file. `model` accepts `mini` or `evo`; omit
it for automatic resolution. Saves preserve overrides, comments and unknown
fields. Saving discovery results never turns an inference into a saved override.
Structured results include `device.model` and `device.model_source`; REPL
`target` reports both. Switching targets resolves the new device before dropping
the previous connection. Startup model and channel overrides do not carry over.

Library callers use `TimeboxClient(model: .mini)` and
`PixelFrame(pixels: pixels, model: .mini)`; image-file loading uses the selected
model automatically. Existing `TimeboxClient()` and `PixelFrame` callers preserve
Evo behavior and saved-design JSON. `TimeboxClient(model: nil)` requests automatic
identification and fails safely when identity is unknown.

## Automatic identification gate: unresolved

No trustworthy hardware classifier is enabled. A renamed Bluetooth device, a
successful write, a generic SPP service, a MAC prefix, or channel 4 alone cannot
establish an original Mini identity. The existing inspector exposes names,
channels, PSMs, handles and attribute counts, rather than a verified product ID.
The protocol sources below instantiate a user-selected model; they do not supply
an independently established Mini/Evo identity-query discriminator.

On 2026-10-19, read-only `inspect --name AKTBR` was attempted with the worktree and
installed executables. Both returned the existing eight-second Bluetooth
scan/query timeout. `inspect --address "$MAC"` for the configured Evo also returned
that timeout. No usable metadata was captured, no RFCOMM control connection was
opened, and no display/clock/alarm command was sent. These failures establish a
capture limitation, not a difference between the devices. No guessed identity
opcode was sent.

A subsequent parent-coordinated standard SDP refresh completed successfully on
both units and exposed seven services each, but neither had a UUID1200 DeviceID
record. The [actual-app and identity follow-up](timebox-model-identity.md) traces
why app name routing, firmware numbers and a modern registration query do not
supply a verified Mini/Evo discriminator. Explicit/config overrides remain valid.

Consequently real hardware without a saved or explicit model fails before display
encoding or writes, suggesting `--model evo` or `--model mini`. Existing CLI users
should add `model: evo` to an Evo config entry or pass `--model evo`. Simulated
hardware has an application-controlled Evo identity. Conflicting evidence is
also an error; explicit overrides are intentional user choices, not detection
proof. Unknown and timed-out detection never selects a different target.

Renamed AKTBR can be targeted directly with an address or a manually configured
logical name. Discovery remains the existing candidate-name filter; `list --all`
shows other paired devices without claiming they are Timeboxes. `list --save`
does not silently classify renamed speakers or connect to devices. Extending
renamed discovery/save awaits verified passive identity evidence.

## Channel and image behavior

The existing SDP resolver is reused, with an explicit `--channel` taking
precedence. The prototype proved channel 4 on AKTBR. The integrated REPL switch-back later
resolved channel 4 from SDP automatically and displayed the smiley; switching to
the Evo resolved channel 1, so the startup channel override did not leak to the
new target. This verifies control-channel resolution on these two devices, not
model identity. No global or inferred channel-4 fallback is introduced, and Evo
channel behavior is unchanged.

Static files use ImageIO frame zero, nearest-neighbor stretching to the model's
size, DeviceRGB and premultiplied alpha over black. Mini channels are truncated to
their high nibbles after conversion. The prototype's resized GIF differed from
Pillow: decoder/color-management/resampling implementations need not produce
identical bytes. Tests assert native-size orientation and controlled resize/alpha
cases instead of copying the mismatched GIF as an equality fixture. GIF playback
is not implied.

## Independent evidence and automated checks

The [validated prototype](https://github.com/AdrieanKhisbe/timebox-studio/blob/dc9b76c4bd1db3d25d34bb6965a5529e1e702e95/timeboxctl/MiniPrototype/README.md)
records user confirmation of red, the 11×11 orientation pattern and the loaded
smiley on AKTBR over Classic channel 4 (2026-10-18). Brightness was transmitted,
but its independent visual effect was not established.

Primary implementation references, pinned to hass-divoom commit
`479d728d1a414a8a9e880bd801fe5c4a6956df53`:

- [Mini command/image implementation](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py)
- [Shared checksum/framing and brightness implementation](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py)

Protocol assertions use independently calculated fixed wire bytes for brightness
42 and color FF0080 at 77%, and explicit RGB444 byte expectations. Coverage includes
reserved-byte escaping, pre-escaping length/checksum, the odd 121st pixel,
orientation, quantization, native image conversion, resize/alpha, old Evo design
JSON, model precedence, unknown/conflicting/timeout failures before I/O, direct
address operation, model/source reporting, config edits/saves, unsupported alarms,
and REPL target switching without encoder leakage. Controlled transport tests run
the actual library and CLI methods. Existing Evo protocol fixtures remain passing.

The initial Mini integration passed77tests and its release build. The later
clock/stopwatch/alarm promotion adds escaped-response and full-record alarm
coverage; see its linked report. Historical integrated observations follow.

## Integrated hardware observations (2026-10-19)

Parent-coordinated testing used AKTBR (`$MAC`), explicit Mini encoding and Classic
RFCOMM channel 4. One-shot `color FF0000 --brightness 80` transmitted 15 bytes; the
user confirmed a solid red display. Separate one-shot `brightness 20` attempts
transmitted 8 bytes each, but the user reported no sustained dimmer result and a
Bluetooth icon around disconnect. These attempts are visually ambiguous, not
standalone brightness-persistence acceptance.

A single persistent REPL then sent `color FF0000 80`, `brightness 20`, and
`brightness 80`, retaining the same connection (15/8/8 transmitted bytes). On the
comparison after restoring 80, the user confirmed the previous display had been
dimmer. This establishes visible brightness 20 versus 80 while the link remains
open. No Mini brightness readback or post-disconnect persistence was established.

The same REPL loaded native 11×11 `orientation.bmp` (193 bytes transmitted).
The user confirmed white top-left, red top edge, green left edge, yellow diagonal
and the blue bottom-right 121st pixel. Loading `smiley.bmp` also transmitted
193 bytes; the user confirmed the yellow smiley. The [orientation](fixtures/mini-orientation.bmp)
and [smiley](fixtures/mini-smiley.bmp) inputs are retained with this report.

A temporary scratch config then supplied logical `main-evo` and `mini` entries
with explicit saved model overrides. The user's real config was unchanged.
Within the same REPL:

- `target main-evo` reported model `evo` from config and resolved SDP channel 1.
  `brightness 30` sent 8 bytes; the user confirmed the Evo dimmed.
- `brightness 100` restored the Evo, then `target mini` reported model `mini`
  from config and automatically resolved SDP channel 4. The smiley image sent
  193 bytes; the user confirmed the smiley returned and the Evo was bright again.

This establishes model/encoder/channel switching in both directions for the
validated operations, with no startup-channel-4 leakage to Evo. Saved overrides
are user choices, not automatic identity detection. At the observation cutoff,
the parent-owned Mini REPL remained connected showing the smiley. The
[redacted observation record](fixtures/mini-integrated-observations.json)
separates transport results from the user's visual confirmation.

The [original Mini integration’s documented limitation](https://github.com/mathoudebine/homeassistant-timebox-mini#limitations)
reports a Bluetooth-status symbol after connection loss. That corroborates a
possible status-screen interference; it does not prove the firmware restores a
brightness setting. The CLI closes a one-shot connection after its post-write
hold, whereas the REPL retains the connection. Its disconnect method sends no
brightness/reset packet. No lifecycle or encoding change follows from these
observations alone.

## Manual acceptance still required

The initial sequence above did not independently test solid green/blue fills
or one-shot image-file rendering. A subsequent merged-dev check confirmed red,
green, blue, brightness, the orientation pattern and one-shot smiley upload. An
additional Evo color/image regression was not performed in that check. Mini
brightness after disconnect remains visually ambiguous; no settings-reset cause
is established. Reliable automatic Mini/Evo identity remains unresolved even
though per-target SDP control-channel resolution succeeded. Capture trustworthy
identity evidence before revisiting the classifier. Additional tests require
coordinated device access; do not send display-changing detection probes or
experimental storage commands.
