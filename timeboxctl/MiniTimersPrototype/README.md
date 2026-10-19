# THROWAWAY: original Mini stopwatch, alarm and countdown

Question: can AKTBR use its native Mini stopwatch/alarm commands through the
existing Classic transport, and can an explicitly host-driven countdown provide
a useful fallback where no native Mini countdown command is established?

Branch `prototype/mini-timers-and-alarm`. This is not production support and
does not remove the Mini capability guards on `dev`. Dry run is the default.

```sh
swift build --product mini-timers-prototype
.build/debug/mini-timers-prototype plan
.build/debug/mini-timers-prototype --send --address "$MAC"
```

The interactive tool keeps one connection open. It prints every native command's
complete escaped frame and any raw replies. `clock` selects the Mini24-hour clock.
`stopwatch stop`, `stopwatch start`, `stopwatch reset` use Mini `45 06 ACTION` (numeric0/1/2 also accepted):
physical testing confirmed0pause,1start/resume,2reset-to-stopped-zero.

`alarm-read` opens a fresh exclusive connection, sends escaped42 and validates
frame delimiters, length, checksum and successful044255 before decoding exactly
three10-byte records. Both the captured Mini response and the current Android
app's OldMode parser establish that layout. The old hass Mini short alarm setter
is not used: its schema is superseded here by the current app's full43record
setter. Unknown/malformed layouts fail; timeout is not an empty alarm list.

`alarm HH:MM` freshly reads all3records, requires slot2disabled, preserves its
sound/trigger/frequency/volume bytes, enables that slot with the supplied time
and weekdaymask0, writes43plus its10bytes, then requires fresh whole-snapshot
readback matching the intended change. Neither other slot may change. Recurrence
and audible behavior still need hardware confirmation; raw trigger1 is preserved.
`alarm off` restores the exact captured original slot2record and verifies all3
records match the baseline. `alarm-next` uses hostlocaltime+2minutes only when
Mini clock matches; `alarm-in2 HH:MM` uses user-reported Mini time+2minutes when
it does not. Minute resolution and user-report delay limit trigger-time precision.
`alarm-watch` pumps Bluetooth for the observation window and restores afterward.
Normal exit also attempts exact restoration; forced termination/power loss cannot
guarantee cleanup, so clear the experimental slot in the official app if interrupted.
The user confirmed there is no alarm to preserve; fresh readback is still mandatory.
No clock synchronization is performed.

`countdown 30` draws white remaining seconds from030 down to a green000 using
the already validated11×11 image encoder. The **host** maintains the timer and
sends images; this is not a native Mini countdown or a device completion sound.
Keep the process running until completion. Prototype range:1–180seconds.

`wait SECONDS` pumps the Bluetooth run loop. `quit` disconnects. No automatic
clock synchronization, volume change, settings backup, save, delete, or retries.
Selecting the clock and stopwatch changes the display. An alarm write changes
the Mini's single alarm setting. Raw RX output is not verified settings readback.

Open `packet-demo.html` for an offline packet/state walkthrough without Bluetooth.
It previews the narrow experiment and cleanup requirement; it does not send.

Primary implementation references:

- [Original Mini implementation, pinned hass-divoom](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py): Mini alarm, stopwatch selector, native countdown explicitly unsupported.
- [Original Mini protocol](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/doc/protocol.md): stopwatch display selector450600.

Stopwatch verdict: native start, pause, resume and reset confirmed on AKTBR. The host-driven30second countdown visibly counted down and ended green. Slot2 at Mini-clock02:52 sounded and fresh readback verified the intended setting with the other2slots unchanged. Fresh readback verified all3alarmrecords exactly restored, including disabled slot2 and unchanged other slots. Bluetooth was then closed. See observations.json. Transport success alone is
not physical confirmation. Production libraries and their Mini guards are unchanged; only a separate executable target and prototype artifacts were added.
