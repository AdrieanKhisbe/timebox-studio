# Live Evo alarm listing

Evidence for [AdrieanKhisbe/timebox-studio#12](https://github.com/AdrieanKhisbe/timebox-studio/issues/12),
investigated 2026-10-18. This extends the earlier T8 alarm investigation: a documented read request and
a real Evo response have now established enumeration without changing alarms.

## Manufacturer and app evidence

[Divoom's Get alarm time page](https://docin.divoom-gz.com/web/#/5/246)
documents a payload-free `42` request, a reply beginning `04 42 55`, and ten
alarm records in that reply. The record layout references the alarm setter.
[Divoom's Set alarm time page](https://docin.divoom-gz.com/web/#/5/247)
defines these ten-byte records:

| Record offset | Meaning |
| --- | --- |
| 0 | Slot, starting at zero |
| 1 | Enabled, 0 or 1 |
| 2–3 | Hour and minute |
| 4 | Weekday mask; Sunday bit 0 through Saturday bit 6 |
| 5–6 | Sound mode and trigger mode |
| 7–8 | Frequency bytes |
| 9 | Volume, 0–100 |

The weekday description refers to repeating days. It does not establish a
separate finite-weekdays flag. The mode documentation gives incomplete names,
and it does not name the live device's mode 3 / trigger 0 combination. Preserve
the numeric modes and frequency bytes; do not invent sound labels, a recurrence
boolean, or an FM number from an unverified endianness assumption.

Both original pages were retrieved successfully from the manufacturer's public
ShowDoc API, which exposes the text behind its JavaScript frontend:
[query page JSON](https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=246),
[record page JSON](https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=247).
Retrieval requires no account. Page metadata reports publication on 2023-08-08.
The [pinned documentation snapshot](https://github.com/ztomer/divoom_control/blob/1b64f0b2a2c300139c3b3e847dfb52ca51cae58a/docs/divoom_docs/alarm_memorial.md)
provides a stable cross-reference to those same page IDs.

Independently, an archived official-app decompile identifies
[`SPP_GET_ALARM_TIME_SCENE` as decimal 66](https://github.com/DavidVentura/divoom/blob/0cb77c83503012fb7f5c8b7d4a52f8eeab398e66/decompiled-sources/SppProc.java#L38)
and [`CmdManager.r()` constructs that request without data](https://github.com/DavidVentura/divoom/blob/0cb77c83503012fb7f5c8b7d4a52f8eeab398e66/decompiled-sources/CmdManager.java#L2073-L2076).
The same builder's setter serializes the ten fields in this order. Its
`SPP_GET_DIALY_TIME_EXT2`/`83` belongs to a different memorial path and is not needed
for alarm enumeration. No guessed opcode or slot probes were sent.

The [Ditoo reader](https://github.com/mert4x4/ditoo-pro-custom-firmware/blob/7eefdd4cc31e163c49c481b5b6aa71f2ef886288/client/ditoo_api.py#L921-L928)
also sends `42` and parses ten-byte records. Its firmware is a different model,
so it corroborates structure rather than Evo support. Do not copy its permissive
truncation of partial records. Its numeric frequency conversion also disagrees
with the app builder and the earlier reference encoders; retain raw bytes.

## Observed Evo result

At **2026-10-18T20:41:34Z**, an isolated Classic probe ran against
the paired `main-evo` (`$MAC`), resolving **RFCOMM channel 1** via SDP. The probe
listened passively for one second, sent exactly the documented request, and
collected replies for five seconds. It wired the existing RFCOMM bridge's receive
callback in a scratch copy; no production alarm setter or device clock command
was involved. An initial sandboxed open failed; the approved outside-sandbox run
succeeded.

```text
TX: 01 03 00 42 45 00 02
RX prefix: 01 69 00 04 42 55
RX suffix: 56 03 02
```

The [complete captured fixture](fixtures/evo-alarm-list-live.json) preserves all
109 bytes. Its frame length is 105; after the reply prefix and checksum there
are exactly **100 data bytes**, ten distinct records with slots **0–9**. The
checksum is `0356` little-endian. This agrees with the manufacturer's complete
ten-record reply, so no terminator, extra per-slot requests, or guessed range is
needed for this Evo response.

Slot 0 is enabled at 10:00 with weekday mask `08` (Wednesday), mode 3, trigger 0,
frequency bytes `00 00`, and volume 50. Slots 1–9 are disabled. These are decoded
device bytes. The user independently confirmed the official app shows the enabled
Wednesday 10:00 alarm and nine disabled slots. No scheduled firing was observed.
The result is not an all-disabled fixture and must not be labelled empty.

The implemented one-shot `alarm list --device main-evo --json` also returned
these ten slots successfully. The implemented REPL then performed two consecutive
`alarm list` reads and resumed a connected `main-evo` target after each. A first
REPL attempt exposed immediate RFCOMM close/reopen timing; servicing the main run
loop for 500 ms around the transition resolved it in the repeated hardware run.
No alarm writes were sent during these checks.

Automated validation: `swift test` passes all 54 tests, including strict record
decoding, framing, timeout/disconnect/cancellation, late replies, JSON/YAML parity,
CLI/REPL routing and existing protocol tests. The release CLI build passes.

## Decoder and query contract

- Send one documented `42` request after installing the receive listener. Match
  replies by command `42`, not any arriving notification. `55` is its documented
  success acknowledgement. Preserve other acknowledgement values as errors.
- Assemble fragmented input and split concatenated frames using length. Validate
  delimiters and checksum before decoding. A timeout, disconnection, rejected
  command, unsupported transport, or malformed frame is an error, never `[]`.
- For this Evo ten-slot format, require all 100 record bytes and exactly one
  record per slot 0–9. Reject truncation, trailing data, duplicate/out-of-range
  IDs, and invalid defined fields. Never expose a partial list as complete.
- Return all ten configured slots, including disabled records. An all-disabled
  device still has ten slot records; expose enabled state explicitly. An empty
  transport payload is not documented as an empty device and must fail.
- Keep unknown mode bytes raw and recurrence unspecified. Report the weekday
  mask and decoded day names. A high weekday bit whose meaning is unknown must
  remain visible or fail explicitly, not be silently discarded.
- Library, one-shot CLI, REPL, and JSON/YAML should use this same decoded model.
  Simulation must be labelled simulated; only live responses can be called read.
  Store no command history as a substitute for a query.

## Remaining acceptance

Listing is implemented before alarm writes. The official-app comparison was
confirmed by the user. Acceptance still needs a change made outside Timebox Studio
followed by a fresh list showing that change. An unused slot must be explicitly
chosen before any such change; none has been selected during this investigation.
An all-disabled response and recurrence behavior are also not captured here.
Synthetic malformed/disabled variants can test decoder boundaries but must be
labelled derived rather than described as physical captures. This evidence does
not complete the write semantics required by
[AdrieanKhisbe/timebox-studio#10](https://github.com/AdrieanKhisbe/timebox-studio/issues/10).

Other sources inspected: the pinned
[node Evo protocol](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/PROTOCOL.md)
documents settings request `46`, not alarm listing; its older MarcG046,
derHeinz and fhem references did not supply an alarm-list decoder in the inspected
revisions. Wi-Fi Pixoo cloud `Alarm/Get` routes and MiniToo firmware-specific
experiments do not establish Evo Classic enumeration. The manufacturer's `42`
documentation plus the direct Evo reply provide the relevant evidence here.
