# Original Mini clock, stopwatch and alarms

Issue: [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20).
Validated on AKTBR (`$MAC`), 2026-10-19, macOS Classic RFCOMM channel4.
SDP chose the channel; the model was explicitly Mini. MiniToo and BLE are outside
this evidence. Reliable automatic model identification remains unresolved.

## Supported commands

```sh
timeboxctl display clock --address "$MAC" --model mini
timeboxctl stopwatch start --address "$MAC" --model mini
timeboxctl stopwatch stop --address "$MAC" --model mini
timeboxctl stopwatch reset --address "$MAC" --model mini
timeboxctl alarm list --address "$MAC" --model mini --json
timeboxctl alarm set 2 --time 07:30 --address "$MAC" --model mini
timeboxctl alarm disable 2 --address "$MAC" --model mini
```

The same commands work in the REPL on its current target. Saved `model: mini`
overrides work as before. The library uses `TimeboxClient(model: .mini)` with
`display(.clock())`, `stopwatch(_:)`, `setAlarm` and `disableAlarm`.
`TimeboxAlarmReader.read(..., model: .mini)` reads an independently owned fresh
Classic connection. Library alarm setters accept a supplied live record and send
one write; the CLI additionally obtains fresh before/after snapshots and verifies
the exact intended record and unchanged other slots.

Mini clock display selects `45 00 01`, its24-hour clock. It does not synchronize
time or offer Evo styles. Stopwatch uses `45 06 ACTION`:0pause,1start/resume,
2reset-to-stopped-zero. No elapsed-time getter is claimed.

## Alarm protocol and preservation

The pinned [prototype `fafb242`](https://github.com/AdrieanKhisbe/timebox-studio/tree/fafb242/timeboxctl/MiniTimersPrototype)
captured a successful escaped `04 42 55` reply with exactly30data bytes: three
10-byte records with IDs0,1,2. The current Android app3.8.40 OldMode alarm parser
explicitly selects three records; its `AlarmViewModel.a`/`CmdManager.y0` path sends
`43` followed by a complete record. The APK hash and source anchors are retained
in the prototype’s source report; decompiled copyrighted sources are not included.
The older short alarm setter from hass-divoom is not used.

Each record is slot, enabled, hour, minute, weekdaymask, raw sound mode, raw trigger
mode, two frequency bytes, volume. Model-specific decoding requires exactly30
Mini bytes or100Evo bytes, every unique slot, and valid enabled/time/volume fields.
Unknown sound/trigger/frequency bytes remain unchanged. Set changes enabled/time/
weekdaymask and optional volume; disable changes only enabled. Mini slot3 and
higher fail before a device query or write. A failed write is not automatically
replayed; readback failure or mismatched other slots never reports success.

OldMode framing escapes interior01/02/03 after calculating length/checksum.
Receive decoding handles fragmented escapes, coalesced frames and the exact
observed `00 05 HELLO 00` greeting at frame boundaries. Other preambles, invalid
escapes, lengths, checksums, envelopes and truncated replies fail closed. Queries
retain fresh-link ownership, cancellation and timeout handling. Missing bytes
are never interpreted as empty/disabled alarms.

`--days` uses the app-backed weekday bits; without it, the mask is0. One mask0
alarm was heard in the prototype. Weekly repetition, alternate sound/trigger
modes and changed volume were not independently exercised. No date/clock change
is implicit in alarm commands. Recurrence remains null in returned readback data
rather than claiming an independently decoded repeat flag.

## Actual observations

The prototype user confirmed native stopwatch start, pause with elapsed retained,
resume, reset to stopped zero, and an audible slot2alarm at02:52 on the Mini’s own
incorrect clock. Fresh readback confirmed only slot2 changed and all three records
were exactly restored afterward. The clock was not corrected.

Production release CLI checks then:

- Read three disabled records through normal `alarm list`.
- Enabled slot2 at its existing00:00setting, confirmed fresh readback, immediately
  disabled it, and compared all three records with the original snapshot: exact
  match. This was a settings round trip, not another audible-trigger test.
- Listed alarms inside the REPL and successfully reconnected its persistent link.
- Displayed the Mini clock, visibly confirmed by the user.
- Reset/started the stopwatch; the user confirmed upward counting. Stop/reset
  returned to stopped zero, also confirmed. Bluetooth was then disconnected.

The [redacted production fixture](fixtures/mini-production-alarm-roundtrip.json)
separates settings readback and user observations. No experimental alarm remains
enabled. No automatic detection, RTC readback or post-power-cycle persistence
claim follows from these checks.

Clock synchronization was added afterward; see the separate
[clock-sync report](mini-clock-sync.md). Native GIF support is covered in the
[animation report](mini-animation.md). Native countdown and display channels/styles
other than bare clock and [light selection](mini-light.md)
retain their Mini unsupported guards. [Live status](mini-status.md) uses the Mini
settings schema. Text now has an explicit
[host-streaming mode](mini-streaming-text.md). The prototype’s image
countdown is explicitly host-driven and is not promoted by this change.
