# Evo settings response investigation

[AdrieanKhisbe/timebox-studio#13](https://github.com/AdrieanKhisbe/timebox-studio/issues/13),
2026-10-19. Built on the framed receive/query contract of
[AdrieanKhisbe/timebox-studio#11](https://github.com/AdrieanKhisbe/timebox-studio/issues/11).

## Sources and field map

Manufacturer [Get light mode, page 288](https://docin.divoom-gz.com/web/#/5/288)
and its [public page JSON](https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=288)
document a payload-free `0x46` request and a successful `04 46 55` reply.
This source explicitly distinguishes lighting brightness from system brightness.
The documented payload extends through index 19:

| Data index | Documented field | Public implementation |
| --- | --- | --- |
| 0 | Display mode | Raw byte and conservative sourced name |
| 1 | Temperature unit | Raw only |
| 2 | VJ selection | Raw only |
| 3–5 | Lighting RGB | Raw only |
| 6 | Lighting brightness | `lightBrightness` / `light_brightness` |
| 7–9 | Lighting effect, switch, music selection | Raw only |
| 10 | System brightness | `brightness` |
| 11–19 | Clock format, RGB, mode and options | Raw only |

Manufacturer [Set light mode, page 287](https://docin.divoom-gz.com/web/#/5/287)
agrees on modes 0 through 5. Its mode 6 describes a scoreboard while page 288
calls mode 6 lyrics. Mode 6 therefore remains unlabeled. Unknown values are
preserved; they are not guessed to be supported display features.

The independent [Evo receiving documentation](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/PROTOCOL.md#receiving-messages)
confirms the request and reply envelope and places the brightness fields at the
same offsets. Its WIP sample contains 22 data bytes. We require the documented
20-byte minimum and preserve all trailing bytes instead of requiring a guessed
fixed firmware revision length. Both exposed brightness values must be 0–100.

The archived app [enum](https://github.com/DavidVentura/divoom/blob/0cb77c83503012fb7f5c8b7d4a52f8eeab398e66/decompiled-sources/SppProc.java)
names command 70 (`0x46`) `SPP_GET_BOX_MODE`, distinct from sleep-scene query
162 (`0xA2`). No sleep command or clock write is part of status.

## Reproducible automated evidence

[Source-derived fixture](fixtures/evo-status-derived.json) substitutes explicit
mode 0, lighting brightness 50 and system brightness 75 into the reference's
placeholder example, then frames it with the documented length/checksum. It is
**synthetic, not a physical capture**. It checks field offset selection with two
different brightness values, independent of any previous outgoing commands.

Unit/integration tests cover fragmentation, unknown and ambiguous mode values,
truncation, corrupt checksums, invalid brightness and boundary values, full raw
extension preservation, timeout/disconnect, one-shot JSON/YAML equivalence,
read-only request bytes, mock rejection and REPL target/resume behavior. The
shared query suite additionally covers cancellation, duplicates, unrelated
responses, stale callbacks and competing writes. These tests need no Bluetooth.

## Hardware acceptance still pending

A coordinated read-only attempt on 2026-10-19 targeted `main-evo` (`$MAC`):

```sh
.build/debug/timeboxctl status --device main-evo --json --timeout 5
```

Opening RFCOMM channel 1 timed out before any query
packet was sent. The transport returned IOReturn `-536870186` / `0xE00002D6`
(RFCOMM channel-open callback timeout); structured output correctly reported
`status: error`, `data.code: connection_failed`. No status reply was captured
and no mode, brightness, alarm or clock settings changed. No retries or alternate
channel probes were performed. The existing macOS speaker/SPP ownership issue
may explain this failure, but was not established by this attempt.

Manufacturer and reference field maps establish the candidate decoder; issue
acceptance still needs a captured response from this Evo and an independently
observed physical/app mode/brightness change followed by a fresh read. Do not
mark the issue complete based on derived fixtures. Automated validation passes
all 75 tests; the release CLI build is recorded with the implementation commit.

Coordinated validation must query `main-evo` without setters, record raw data and
mode/brightness, then have the user change the relevant setting with physical
controls or the official app. Disconnect competing controllers before each query.
Compare the second live reply with that observed change. Brightness writes from
Timebox Studio itself are not independent validation. MACs in published reports
must be `$MAC`. Do not claim other fields, BLE, or model identity from this test.
