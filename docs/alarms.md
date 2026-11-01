# Read live Evo alarms

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
connection. This implements the alarm-specific receive path; general settings
queries, BLE response decoding and multiplexed queries remain outside its scope.

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
recurrence/firing remain manual acceptance steps. Alarm writes are still a
separate issue.
