# Evo alarms

```sh
timeboxctl alarm set 2 --time 07:30                     # once, device-local time
timeboxctl alarm set 2 --time 07:30 --days mon,tue       # weekly on Monday and Tuesday
timeboxctl alarm disable 2
```

Slots are 0 through 9. With no `--days`, the alarm fires once. With `--days`,
it repeats weekly on those weekdays; no recurrence flag is needed. Finite
weekday schedules are outside this interface after the app investigation. See
[finite weekday findings](validation/evo-finite-weekday-follow-up.md).

Set and disable first read all slots, preserve the selected slot's sound mode,
trigger mode, frequency bytes and existing volume, then write only that slot and
query again. Disable changes enabled state only, retaining time and all other
fields. It is not deletion. `--volume 0..100` explicitly changes volume; there are
no named sound options while their wire values remain unverified. Setting an
alarm never synchronizes the device clock. Use the Timebox's local wall clock.

Both operations return `sent` only after transport success and matching live
readback. JSON/YAML include `data.alarm` from that read, `readback_matches: true`,
the slot and byte count. A failed/mismatched readback is an error explicitly
stating that the packet was sent; inspect `alarm list` for current state. Stored
readback is not proof of a firing. `--mock` cannot preserve unknown device sound
state and returns `unsupported` rather than inventing default fields.

The same set/disable syntax works inside the REPL, using its current target.
Normal selectors, config and output flags apply to one-shot commands. Typed
Swift callers create `TimeboxAlarmSchedule(hour:minute:weekdays:)` and
use `TimeboxClient.setAlarm(_:schedule:volume:)` or `disableAlarm(_:)` with a fresh
live `TimeboxAlarm` record. The library encoder preserves its other fields; those
write helpers report transport completion. Obtain fresh readback through
`TimeboxAlarmReader` when validating stored state.

The authorized slot 2 experiment fired with no weekdays and auto-disabled at its
scheduled minute; the user confirmed it worked. All exposed fields were restored
and read back. See [write validation](validation/evo-alarm-write-evidence.md).
Weekly repetition, missed-time boundaries and persistence across restarts still
require observation. Finite weekday scheduling has no established wire encoding.

## Read live alarms

```sh
timeboxctl alarm list
timeboxctl alarm list --device main-evo --json
timeboxctl alarm list --name main-evo --yml
timeboxctl alarm list --address AA:BB:CC:DD:EE:01 --timeout 5
```

Normal selector precedence, `--config PATH`, and `--channel` apply. Timeout defaults
to five seconds after the request is written; allowed values are greater than
zero and at most 60 seconds. Connection/open and write timeouts are separate.
macOS Classic Bluetooth is supported; mock mode returns `unsupported` because it
has no real alarm state. No alarm or clock settings are changed.

The manufacturer documents a single `42` query returning all ten zero-based slots.
The observed Evo reply confirms this. Listing includes disabled slots: a device
with no enabled alarms still returns ten records. Missing, truncated or malformed
data, timeout and disconnection are errors, never a successful empty array. See
[protocol evidence and the live fixture](validation/evo-alarm-listing.md).

JSON/YAML return `command: alarm list`, `status: ok`, the selected `device`, and
`data.alarms`. Every record has `slot`, `enabled`, `time` (HH:MM), `hour`, `minute`,
`weekday_mask`, known `weekdays`, `volume`, `sound_mode_raw`, `trigger_mode_raw`,
`frequency_bytes`, and `recurrence: null`. The raw mask preserves unknown bits.
Sound/trigger meanings, FM conversion and independent recurrence semantics have
not been verified, so the CLI does not invent names or a once/recurring boolean.
There is no cached/local-history substitute for these device reads.

Inside the REPL use `alarm list [--timeout SECONDS]`. It reads the current target.
The read uses a fresh connection and then resumes the persistent session. A failed
read leaves that target disconnected; use `target NAME` to reconnect explicitly.
The startup channel override belongs to the initial connection; the alarm read
and resumed connection resolve the selected device's SDP channel.

There is no request identifier in these replies. Each read owns a dedicated
connection, closes it on success, timeout, cancellation or decoding failure, and
never retries on that link. This prevents stale/duplicate responses from matching
a later identical query. A matching command and validated frame are required;
unrelated replies do not complete the read. Writes must not interleave on a query
connection. The shared `TimeboxQueryReader` implements framed receive handling and ownership;
`TimeboxQuery.alarms` supplies the verified alarm request and typed record decoder.
Settings field decoding, BLE response decoding and multiplexed queries require
separate evidence. See [device query contract](device-queries.md).

Swift apps can read directly on the main actor:

```swift
let alarms = try await TimeboxAlarmReader.read(device: device, timeout: 5)
```

This opens/closes a dedicated Classic connection. Disconnect competing controllers
first. Cancellation is checked around connection and during reply waiting;
Classic connection/write operations retain their existing bounded timeouts.
For an already connected, exclusively owned Classic session on the main thread,
`TimeboxAlarmReader.read(from: transport)` provides the same decoder and closes
the supplied transport on completion. A pre-existing receive handler is rejected
without replacing it. Protocol parsing lives in TimeboxKit; transport/query
handling lives in TimeboxBluetooth.

The live capture, user-confirmed official-app comparison and decoder tests establish
enumeration. An external app edit followed by readback, and observation of
recurrence behavior remains subject to manual acceptance. Finite weekday writes
have no established wire encoding.
