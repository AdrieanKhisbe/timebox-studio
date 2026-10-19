# Evo display channels: implemented subset and evidence gates

Issue: [AdrieanKhisbe/timebox-studio#8](https://github.com/AdrieanKhisbe/timebox-studio/issues/8).
Date: 2026-10-19. Parent-coordinated light/clock observations are recorded below.
This is a partial implementation; the issue is not complete until the blocked
interfaces and physical acceptance are settled.

## Current interfaces

| Operation | Behavior |
| --- | --- |
| `display clock --style 0..5` | Complete clock profile: selected reference style, time on, weather/temperature/calendar off, white RGB. |
| `display light --color RGB [--brightness N]` | Complete plain-light profile: supplied color, brightness 100 if omitted, power on. |
| `display light --brightness N` | Complete plain-light profile with white RGB, not preservation of the existing color. |
| `display design` | Select the custom channel with `45 05`; does not choose a tab or enumerate stored content. |
| Bare `display clock`, `display light` | Fresh settings read followed by complete re-encoding of the target channel’s stored profile. Unknown layouts/flags fail before control writes. |
| `design ID` | IDs0–2, gated by a fresh exact `BD18 → 18 01` capability response, then custom channel plus `BD17 ID`. |
| `effect ID`, bare `display effects` | Historical VJ interface under investigation: effect9 stayed solid blue on this Evo; effect0 attempts had no positive confirmation; no supported substitute or offset is established. |

Normal target/config selectors and JSON/YAML output apply. REPL accepts the same
syntax using its selected target. Existing `color` and `brightness` are unchanged.
Swift callers use `TimeboxClient.display(_:)`, with `TimeboxDisplay`, named
`TimeboxClockStyle` and `TimeboxEffect` values. The encoder owns validation, not
the transport or separate CLI packet templates.

The clock profile contains the reference format byte1, followed by the style,
checkboxes and white RGB. It sends neither a device-time update nor the separate
hour-format command; the manufacturer says the clock's format field is handled
separately. Applying the profile intentionally replaces the listed visual
options. It must not be described as a style-only patch preserving unread state.
Light defaults reproduce the established plain-color packet shape and explicit
reference defaults; they are not inferred from a live settings query.

The reference catalogues define six clock styles and sixteen named legacy VJ
effects. All six clock styles were visually confirmed on this Evo. The legacy
effect fixtures are source evidence only: effect9 stayed solid blue; effect0 attempts did not yield positive confirmation.
Mode3 VJ must not be silently remapped to mode4 audio equalizer, and historical
effect10 must not be described as the countdown timer.

## Sources and independent fixtures

Pinned Evo-specific reference commit:
`2a086b86feaca1b544029f97803336579f0d3a25`.

- [Types/catalogues](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/src/types.ts)
- [Clock profile encoder](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/src/channels/time.ts)
- [Clock golden](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/test/channels/time.spec.ts)
- [Custom-channel golden](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/test/channels/custom.spec.ts)
- [Effects goldens](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/test/channels/vjeffects.spec.ts)

The [manufacturer mode setter](https://docin.divoom-gz.com/web/#/5/287) lists
clock/light/effect fields and the custom mode without additional fields. The
[settings response](https://docin.divoom-gz.com/web/#/5/288) describes current
mode/profile fields but does not independently establish omitted-field retention.
Both are multi-device protocol references, so actual firmware acceptance remains
separate. Their readable JSON is available via the official page/info endpoint.

The [hass-divoom multi-model implementation](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py)
selects custom mode before an optional external design-tab operation. It does not
establish an Evo-supported tab limit. The old Evo protocol text describes short
channel switching, while the manufacturer's field descriptions and modern app
full-profile encoders do not establish its preservation semantics on this Evo.
The explicit unsupported gates avoid silently filling missing settings with zeros.

Independent frozen fixtures used by tests:

```text
custom channel: 01 04 00 45 05 4E 00 02
clock style 0:  01 0D 00 45 00 01 00 01 00 00 00 FF FF FF 51 03 02
VJ effect 0:    01 05 00 45 03 00 4D 00 02
VJ effect10:   01 05 00 45 03 0A 57 00 02
```

Tests exercise clock/custom golden fixtures, invalid IDs and percentages, fresh
capability gates and profile mapping, fragmented/coalesced selector noise, malformed
matching replies, cancellation, partial writes, connection lifecycle and CLI/REPL
equivalence. Legacy VJ requests are tested for rejection before I/O. Tests run without hardware.
The release build and full suite are recorded with the implementation commit.

## Integrated light/clock observations (2026-10-19)

The parent tested main-evo (`$MAC`) on Classic channel 1; the investigating agent
performed no device access. `display light --color 0000FF --brightness 30`
transmitted 17 bytes, and the user confirmed a dim blue display. A subsequent
20-byte settings response reported configured channel 1, blue RGB, brightness
values 30 at data 6 and data 10, effect 0 and power 1.

`display clock --style 0` then `brightness 100` ran serially (17-byte profile,
8-byte brightness packet). The user confirmed a white clock. Readback reported
configured channel 0, white RGB, style 0, time checkbox 1, other checkboxes 0, and
brightness 100 at both positions. The test intentionally replaced the previous
clock color/style with the announced complete profile; it did not preserve them.

An earlier settings response had reported channel 0 while a user-confirmed Hello
animation was visible. Therefore getter mode is configured channel, not proof
of the currently rendered overlay/pixels. Both brightness fields co-varied;
this sequence does not establish independent brightness-field semantics.
The [redacted observation record](fixtures/evo-display-integrated-observations.json)
retains the raw data arrays and user confirmations. Exact notification chunks and
timestamps were not captured. The additional parent-coordinated observations below extend this initial sequence.

## Actual app selector and tab evidence

Actual Divoom APK3.8.40, SHA256
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`,
was inspected with JADX 1.5.6. Decompiled copyrighted code remains outside Git.
`DeviceFunction.DeviceTypeEnum.setDeviceMode` routes the original Evo through its
TiVi architecture. `LightCommonMainFragment.H2` switches channels through
`LightViewModel`:

- Light `v()` serializes the cached RGB/level/effect/power fields with
  `CmdManager.A2`, not a bare selector.
- Clock `x()` serializes cached clock fields with `CmdManager.E2`.
- VJ `y()` sends the cached effect index with `CmdManager.G2`.

This source supports explicit full-profile re-encoding, but it does not prove
that short clock/light/effect selectors preserve settings. Fresh read/complete
write implements the explicit preservation contract below; it does not assume
that a bare short selector retains omitted fields.

`LightCustomFragment` has exactly three page buttons, calling its selection
handler with indices 0,1,2; that handler calls `CmdManager.q1(index)` which emits
external subcommand `BD 17 index`. However it gates selection on a capability
flag, initially false for the original Evo. `CmdManager.U0()` requests
`BD 18` (GET_NEW_POWER_ON_CHANNEL); the `u.i` reply parser enables the flag only
for payload `18 01`. This provides a bounded app-backed investigation candidate,
not universal firmware support for tab indices.

The source-established read-only capability request candidate is
`01 04 00 BD 18 D9 00 02`. Capture commandBD's response and validate that its
payload begins 18 before interpreting the flag. A timeout, unsupported reply or
unknown value is unknown capability, not a reason to try arbitrary indices.
Parent-coordinated selection tests then exercised indices0–2 without replacing
existing artwork; results appear below. This investigating agent sent no
capability query or tab-selection packet.

## Fresh-read preservation and capability contract

Bare clock/light selection reads a fresh exclusive `0x46` snapshot. Exactly the
verified20-byte layout is accepted; extra fields are retained by status reporting
but rejected for re-encoding rather than dropped. Clock setters copy format11,
style15, checkboxes16–19 and RGB12–14 into the source-established setter order.
Light setters copy RGB3–5, level6, effect7 and power8, followed by the established
three reserved zero bytes. Unknown stored style/light-effect bytes are copied;
invalid boolean fields are rejected. An unknown currently configured channel does
not invalidate a separately readable target profile. No device clock is set.

The read connection closes before a separate control connection writes a fully
encoded packet. Indexed design selection similarly reads fresh capability and
sends no channel/tab packet unless the exact flag is1. Timeout, malformed replies,
unknown flags and other BD subcommands cannot enable selection. Other selectors
are ignored while waiting; malformed matching replies fail. The app supplies the
bounded0–2 range, not a claim of universal firmware support or unique content.

CLI/REPL use the same writer as the library. The persistent REPL temporarily
releases its connection for the read/write sequence and resumes the same target
and channel only after success. A failure leaves it disconnected. Connected Swift
clients follow the same lifecycle; injected/custom transports need an explicit
query/display adapter, and unavailable platform adapters fail explicitly. These
fresh Classic query semantics are not claimed for BLE or Mini. Explicit clock/
light profiles continue using the existing transport without a live read.
Cancellation and read failures send no control packets. A failure after the first
of two design writes reports partial completion; no rollback is invented.

## Additional physical observations and remaining acceptance

The parent confirmed clock styles0–5: white, rainbow, boxed, square analog,
inverse and round analog. Returning from a rainbow clock after five seconds to
`45 05` restored the same visible custom content. This verifies visible retention,
not an independently read current tab index or persistence after restart.

The source-backed capability request returned `18 01`. Parent diagnostic tab0
showed rotating scenes; tab1 showed visibly different content. Tab2 looked the
same as tab1, so duplicate content and ignored selection remain indistinguishable.
No upload, save, delete, enumeration, restart or artwork replacement occurred.

`45 03 00` was sent twice from clock and again from blue light;
`45 03 09` also left the display solid blue. Effect0 attempts had no positive visible confirmation and status remained the
previous configured channel; effect9 was explicitly confirmed still solid blue. APK3.8.40
`LightVJFragment` maps its sixteen buttons directly to indices0–15, then
`LightViewModel.y → CmdManager.G2`; the setter is exactly `45 03 index`.
There is no evidence for +1 numbering or missing padding. More significantly,
`LightCommonMainFragment.standardLoad` does not add that VJ fragment/tab.
`LightConfigFragment.B2` omits VJ from visible choices while retaining slot3 in
its separate protocol-index map. This supports treating the retained VJ path as
legacy, not claiming that all IDs work on this firmware. It does not prove every
ID fails. No speculative replacement packet is implemented. Both explicit and bare typed
effects operations return unsupported before any query, connection or control
write; the raw diagnostic escape hatch remains available for deliberate research.

The production CLI fresh-read writer restored the existing round analog clock
(style5, 17 bytes, preserved_profile true), then the existing solid blue/full
brightness light (17 bytes). Both were visually confirmed. Production `design 0`
read capability and sent two control packets totaling17 bytes; animated content
was confirmed. A typed `effect 9` request returned unsupported locally without
control output.

Remaining physical acceptance: exercise these live operations in a persistent
REPL to confirm reconnection on this device and compare complete stored profile
readbacks. The controlled transport tests cover those lifecycle paths.
Tab2’s distinct behavior and VJ support remain unresolved. Transport completion
is not visible validation. The parent retains the exclusive hardware lease;
this investigating agent performed no device access.

No persistence/enumeration support is inferred. That separate investigation is
[AdrieanKhisbe/timebox-studio#19](https://github.com/AdrieanKhisbe/timebox-studio/issues/19).

Automated validation for this follow-up: 94 tests passed; release build passed.
