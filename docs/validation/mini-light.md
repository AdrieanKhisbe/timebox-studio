# Original Mini light-mode selection

Tracks [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20)
and [AdrieanKhisbe/timebox-studio#8](https://github.com/AdrieanKhisbe/timebox-studio/issues/8).
Date: 2026-10-19. Builds on the [verified Mini settings query](mini-status.md).

```sh
timeboxctl display light --address "$MAC" --model mini
timeboxctl display light --color 0000FF --brightness 80 --address "$MAC" --model mini
```

Bare `display light` reads fresh Mini settings, validates their layout, and selects
the stored RGB, light brightness and variant. It does not substitute white/100
defaults or write system brightness. Either explicit color or brightness option
instead applies a complete plain-light profile: missing color is white, missing
light level is100, and variant0 is fixed color. This matches the existing explicit
profile contract. Normal selectors, JSON/YAML, timeout and REPL behavior apply.

Bare selection needs live Classic reads and cannot use mock state. The fresh
query is fully validated before opening a separate control connection; errors
send no control packet and never fall back to defaults. REPL resumption preserves
the selected target/channel. The library supports `TimeboxClient.display(.light())`
and explicit `.light(color:brightnessPercent:)`; Mini bare clock remains its
already verified no-query24-hour command. Model-tagged profiles cannot be encoded
through the other model's encoder.

## Primary protocol evidence

In official Android3.8.40, `LightViewModel.r` passes the Mini's stored light RGB
(status3–5), level6 and variant22 into `CmdManager.x2`. It emits exactly
`45 02 R G B LEVEL VARIANT`, then OldMode escaping. APK SHA256:
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`.
The pinned [Mini reference encoder](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py)
independently uses the same light selector and fields. This is not the Evo's
`45 01` profile or its power flag layout.

The app's ThreeFragment controls offer variants0–4; fixed-color controls use0.
Other variant effect meanings remain unverified and are not named or exposed
as new public options. Preservation accepts only0–4 and the exact23-byte schema.
Unknown variants or layout extensions are retained by `status` but rejected for
activation. The write must not guess that variant22 is a boolean power field.
No copyrighted decompiled source is distributed.

The independently calculated blue/80/variant0 frame is
`01 09 00 45 03 05 00 00 FF 50 00 9F 03 04 02`.
The length/checksum cover unescaped bytes; this exactly matches the previously
validated Mini solid-color operation. Tests cover that fixture, profile/model
separation, invalid brightness/variants/extensions, read failures, no default
fallback, query-free explicit profiles, mock rejection for bare selection,
REPL channel retention and library reconnect only after successful preparation.
All 184 tests and the release build pass.

## Physical stored-profile acceptance

On AKTBR (`$MAC`), the release CLI captured a fresh baseline: clock mode0,
light RGB0000FF, light level80, variant0 and system brightness20. The parent
then ran bare `display light` through a persistent REPL on SDP-resolved channel4,
with explicit Mini model. It performed its fresh settings read and one control
write; the user confirmed solid blue.

A subsequent fresh query changed only configured mode byte0 from0 to2. All stored
RGB/level/variant fields, system brightness and other settings were unchanged.
After `display clock`, a final fresh query matched all23 baseline bytes exactly.
All connections closed; no clock-time, alarm or storage writes occurred.

[The redacted capture](fixtures/mini-light-profile-live.json) retains actual
decoded data from CLI output, not original radio chunks/envelopes. This validates
the stored plain-blue variant0 path; other variants0–4 combinations, unknown
firmware revisions, physical write failure and persistence remain unverified.
