# Original Timebox Mini integration

Issue: [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20).
Investigation and implementation date: 2026-10-19.

## Supported interface

The original Mini uses 11×11 pixels, high-four-bit RGB444 quantization and escaped
interior bytes. Evo retains its 16×16 palette encoding and unescaped framing.
Brightness, solid color and static files are integrated into the ordinary CLI,
REPL and `TimeboxClient`. Raw already-framed packets remain an escape hatch.
Mini alarms, other channels, animation, live queries, MiniToo and Mini BLE/iOS
have no compatibility claim. Typed Mini alarm commands fail before device I/O;
Mini library connections on iOS fail before BLE connection.

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
precedence. The prototype proved channel 4 on AKTBR; this investigation did not
establish that Mini SDP chooses that endpoint automatically. Supply `--channel 4`
for the previously validated device. No global or inferred channel-4 fallback is
introduced, and Evo channel behavior is unchanged.

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

Validation: 77 tests pass; the release CLI build passes. Production Mini hardware acceptance is still pending;
prototype observations do not substitute for exercising the integrated path.

## Manual acceptance still required

With user coordination, run one-shot CLI and REPL on AKTBR using the explicit
Mini override and verified channel. Observe distinct brightness levels, red/green
fills, native orientation including the bottom-right 121st pixel, and an image
file. Switch REPL targets to a configured Evo and back; repeat Evo baseline
brightness/color/image checks. Record the real endpoint/channel and human visual
observations separately from transport success. Capture read-only identity/SDP
metadata once the timeout is resolved before revisiting automatic detection.
Do not send display-changing detection probes or experimental storage commands.
