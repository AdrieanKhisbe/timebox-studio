# Original Mini live settings query

Tracks [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20)
and [AdrieanKhisbe/timebox-studio#13](https://github.com/AdrieanKhisbe/timebox-studio/issues/13).
Investigation date: 2026-10-19. Original 11×11 Mini, Classic RFCOMM; no MiniToo or
BLE compatibility claim.

```sh
timeboxctl status --address "$MAC" --model mini --json
```

Normal target selection and JSON/YAML apply. REPL `status` reads its current
target over a fresh query connection, then resumes the same control channel on
success. Failed reads leave it disconnected. The library exposes
`TimeboxQuery<TimeboxStatus>.status(model: .mini)` and
`TimeboxStatusReader.read(..., model: .mini)`. Existing Evo entry points remain.

## Primary source and field map

The official Android app 3.8.40 `CmdManager.A` sends opcode46 without arguments.
Its successful reply route is `04 46 55` into `u.j`. Original TIMEBOX_MIN selects
OldMode/MiniUiArch; the OldMode branch uses `com.divoom.Divoom.bluetooth.n`,
separate from the adjacent NewMode schema. APK SHA256:
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`.
Inspected with JADX1.5.6; copyrighted decompiled Java stays outside Git.

The independently calculated complete request is `01 03 06 00 46 49 00 02`.
Framing and checksum apply to unescaped bytes; the Mini greeting and interior
escaping are handled by the existing strict response decoder.

Indices below refer only to decoded reply data, excluding the envelope and CRC:

| Offset | Mini interpretation | Public behavior |
| --- | --- | --- |
| 0 | Configured channel | `mode_raw`, model-specific `mode` label |
| 1–5 | Temperature unit, light selection, light RGB | Raw only |
| 6 | Light brightness/level | `light_brightness`, validated0–100 |
| 7 | Sound-light selection | Raw only |
| 8 | System brightness | `brightness`, validated0–100; Evo uses10 |
| 9–21 | Clock format, clock/temperature/sound-light RGB | Raw only |
| 22 | Plain-light variant | Raw only; not an established power boolean |

The app reads through data22 but pads out-of-bounds accesses against its whole
framed array. Production requires at least23 actual data bytes instead: checksum
and tail bytes must never become settings, and missing fields never become zero.
Extensions remain in `raw_data`; unknown modes remain numeric with a null label.
An Evo-shaped20-byte reply is not accepted as a Mini status record.

The Mini UI maps returned channel to pages0–5: clock, temperature, plain light,
special light, sound light and custom. Those are source-backed labels, not a
claim that all corresponding write commands are implemented or validated.
Mode6 stays unknown; the shared enum must not override the Mini-specific page
mapping. The pinned [original Mini protocol](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/doc/protocol.md)
and [Mini reference encoder](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py)
independently corroborate clock0, temperature1, light2 and OldMode framing; the
full status schema comes from the current first-party app.

The result describes configured state, not pixels, visible media overlays,
stopwatch progress, RTC time, model identity or stored-content enumeration.
Mini status cannot be passed into an Evo profile-preservation operation.

## Automated and hardware evidence

A synthetic source-derived record deliberately separates light brightness25,
system75 at8 and a non-brightness231 at10. Independent escaped wire bytes include
reserved field and checksum bytes. Tests cover framing/greeting fragmentation,
short or malformed replies, invalid brightness, raw extensions/unknown modes,
CLI formatting, timeout/disconnect and REPL Mini/Evo switching with channel
retention. These fixtures are calculated, not hardware captures.

## Physical validation on AKTBR

The parent used the release CLI, explicit Mini model and SDP-resolved channel4.
The first read-only query returned exactly23 data bytes: configured clock,
system brightness20 and light level80. The two brightness values were distinct.
After raising system brightness to80, a fresh query changed only byte8; the user
confirmed the clock was noticeably brighter. Restoring20 and selecting the
already stored blue-light profile (RGB0000FF, level80, variant0) returned mode2;
the user confirmed solid blue. Selecting clock restored mode0.

| Stage | Mode raw | System | Light | Changed offsets from baseline |
| --- | --- | --- | --- | --- |
| Baseline | 0 | 20 | 80 | none |
| Brighter clock | 0 | 80 | 80 | 8 |
| Blue light, system restored | 2 | 20 | 80 | 0 |
| Clock restored | 0 | 20 | 80 | none |

The final fresh query matched all23 baseline bytes exactly, including stored
profile colors and options. No clock time, alarm or storage writes were sent.
All query connections closed. [The redacted fixture](fixtures/mini-status-live.json)
preserves exact decoded payloads from CLI output; original radio notification
chunks/envelopes were not logged. Regression frames are explicitly reconstructed.
This isolates the Mini system-brightness field and validates clock/light labels;
it does not independently change/isolate the light-level field or validate modes1,
3–5, rendered overlays, RTC reads, unknown firmware extensions or persistence
across a power cycle. The full177-test suite and release build passed before
the physical check; the final178-test suite includes captured-payload regression.
