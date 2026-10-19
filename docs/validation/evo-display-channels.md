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
| `effect 0..15` | Select the VJ channel with an identifier from the Evo-specific named effect catalogue. |
| Bare `display clock`, `display light`, `display effects` | Unsupported before connection/write while omitted-field retention is unverified. |
| `design ID` | Unsupported before connection/write: no verified Evo tab range or numbering is established. |

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

The reference catalogues define six clock styles and sixteen named effects.
Their bounds are evidence from that Evo-specific implementation, not universal
firmware limits or a claim that this user's Evo has visually validated every ID.
Arbitrary additional byte values are rejected. Effect10 is a built-in VJ effect;
it does not start the device's countdown timer.

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

Tests exercise those fixtures, meaningful invalid IDs and percentages,
unsupported preservation/index requests before device I/O, the actual library
transport boundary, and ordinary CLI/REPL equivalence. Tests run without hardware.
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
timestamps were not captured. Styles 1–5, VJ effects, custom retention and design
indices remain unverified by this session.

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
write is a possible future preservation contract only after field/firmware
behavior is verified; no guessed defaults implement preservation here.

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
Only after positive capability evidence should parent-coordinated non-writing
selection tests consider indices 0–2, preserving existing custom artwork. This
investigating agent sent no capability query or tab-selection packet.

## Manual acceptance / remaining work

Only after coordinating access to main-evo:

1. Record existing visible state and live settings/app profile. Do not change
   device time, alarms or stored custom artwork.
2. Apply an explicit clock profile for each proposed style; record what actually
   appears and which firmware accepted it. Compare returned settings if available.
3. Apply explicit plain-light RGB/brightness profiles; observe visible effects and
   record that full profiles replace the documented omitted options.
4. Select custom channel and verify existing content and tab retention, without
   uploading/replacing a custom item. Verify each proposed numbered VJ effect.
5. Resolve short clock/light/effect behavior using source-backed app captures and
   current settings before/after; only then remove the corresponding unsupported
   gate or revise the contract with the user. Do not guess complete packets to
   simulate preservation. Establish actual design-tab IDs separately before
   enabling `design ID`.
6. Repeat through CLI and persistent REPL, switching channels in both directions;
   distinguish visible confirmation from completed RFCOMM writes.

No persistence/enumeration support is inferred. That separate investigation is
[AdrieanKhisbe/timebox-studio#19](https://github.com/AdrieanKhisbe/timebox-studio/issues/19).
