# Evo display channels: implemented subset and evidence gates

Issue: [AdrieanKhisbe/timebox-studio#8](https://github.com/AdrieanKhisbe/timebox-studio/issues/8).
Date: 2026-10-19. No new display writes or hardware observations were performed.
This is a partial implementation; the issue is not complete until the blocked
interfaces and physical acceptance are settled.

## Current interfaces

| Operation | Behavior |
| --- | --- |
| `display clock --style 0..5` | Complete clock profile: selected reference style, time on, weather/temperature/calendar off, white RGB. |
| `display light --color RGB [--brightness N]` | Complete plain-light profile: supplied color, brightness100 if omitted, power on. |
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
clock style0:  01 0D 00 45 00 01 00 01 00 00 00 FF FF FF 51 03 02
VJ effect0:    01 05 00 45 03 00 4D 00 02
VJ effect10:   01 05 00 45 03 0A 57 00 02
```

Tests exercise those fixtures, meaningful invalid IDs and percentages,
unsupported preservation/index requests before device I/O, the actual library
transport boundary, and ordinary CLI/REPL equivalence. Tests run without hardware.
The release build and full suite are recorded with the implementation commit.

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
