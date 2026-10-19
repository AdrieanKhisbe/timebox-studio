# Evo local clock synchronization observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#15](https://github.com/AdrieanKhisbe/timebox-studio/issues/15).

The parent exclusively operated logical target `main-evo` / `$MAC`, RFCOMM channel 1, after explicitly announcing the clock-setting operation. The command was the clock-and-timers branch's debug CLI: `timeboxctl time sync --device main-evo --json`. It completed a 15-byte transmission. No alarm configuration was changed by this test.

The device had the previously confirmed white clock display style 0. Asked whether its displayed time matched the Mac's current local time around 20:04 CEST, the user answered yes. This accepts visible local time synchronization for that session. The display did not show date or weekday, so physical date/weekday correctness remains unvalidated; packet fixtures independently test their encoding.

## Snapshot limits

A host-only helper recorded **after** the send: `2026-10-19T20:04:08.843896+02:00`, CEST (UTC+02), Gregorian Monday / weekday 1. Its reference payload and packet were computed from that later host instant, not captured from the actual send. Do not present them as the transmitted packet or infer the exact send second from them.

The attempted before-snapshot command failed because its output argument was omitted; no before host baseline was retained. Consequently there is no before/after timing bracket and no recorded original device clock baseline or exact restoration value. There is no implemented device-clock readback API. The human clock comparison is approximate, not a precision/drift measurement.

Final observed presentation: white clock style 0, brightness 100. Not validated: physical date/weekday, drift, exact second alignment, power-cycle persistence, preferred-calendar differences on hardware, future timezone/DST changes, or ongoing synchronization. The operation intentionally sends one local Gregorian wall-clock snapshot without a timezone identifier. It does not change the Mac's clock or establish automatic future maintenance.

Four focused deterministic clock tests passed before the parent test (year-byte and weekday fixture, local calendar boundaries, injected single snapshot and CLI/REPL behavior). This report update is documentation only; the implementation agent performed no hardware access.
