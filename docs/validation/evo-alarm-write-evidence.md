# Evo alarm writes: evidence and test plan

For [AdrieanKhisbe/timebox-studio#10](https://github.com/AdrieanKhisbe/timebox-studio/issues/10),
investigated 2026-10-18. Source findings below are supplemented by the authorized
slot 2 experiment: firing, automatic disable, and restoration were observed.

## Established wire fields

[Divoom's setter documentation](https://docin.divoom-gz.com/web/#/5/247)
([public JSON text](https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=247))
defines `43` followed by ten bytes:

```text
slot enabled hour minute weekdayMask soundMode triggerMode frequency0 frequency1 volume
```

Slot numbering starts at zero. Status is 1 for enabled and 0 for disabled; volume
is 0–100. Day bits start with Sunday at bit 0 and end with Saturday at bit 6.
The documentation describes selected weekdays as repeating days. It identifies
mode 0 and trigger values 1/4 incompletely; it does not name every sound or define
an independent recurrence flag.

The [archived app setter](https://github.com/DavidVentura/divoom/blob/0cb77c83503012fb7f5c8b7d4a52f8eeab398e66/decompiled-sources/CmdManager.java#L1067-L1094)
independently serializes that same ten-byte record. Its frequency representation
is a decimal pair, not an ordinary little-endian integer. Preserve existing raw
frequency bytes when the command does not explicitly change sound settings.

The [newer app-derived serializer](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/src/protocol/alarm.rs)
also carries the full record, including enabled state. Its
[app surface inventory](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/docs/android-surface.json)
records alarm-editor sound labels, but does not map them to numeric mode/trigger
pairs. Those labels alone cannot establish named Evo sound options or defaults.

## What remains an inference

The reference encoders emit mask zero when no weekdays are supplied. The
authorized near-future Evo test below now establishes a firing followed by
automatic disable for that encoding. The inspected manufacturer page does not
establish its past-time boundary or restart behavior; the single near-future
test does not close those remaining cases.

There is no established wire encoding for independent finite weekday firings
such as next Monday once plus next Tuesday once. Do not treat bit `80`, sound
mode, or trigger mode as a recurrence toggle. A supported weekly mask must not
be silently substituted for the requested finite semantics.

The user explicitly chose to keep finite weekdays blocked and investigate
further. Implement no-days once and documented weekly masks through
`--days ... --recurring` (alias `--recurrent`), while explicitly rejecting
`--days` without recurrence as unsupported before any alarm write. Finite
weekdays remain an open requirement of the original issue, not a removed
feature. The issue remains partially complete until their encoding is settled.

## Authorized slot 2 experiment

The user explicitly selected **slot 2** for an alarm two minutes ahead.
The test used local HH:MM two clock minutes ahead; at 23:02:53 this was 23:04,
about 67 seconds later because the wire time has minute resolution. The
acceptance sequence was:

1. Read all ten slots and retain the exact slot 2 record. Abort if it has changed
   from the expected disabled state; retain the other nine records for comparison.
2. Use the Evo's local wall clock. Reading the Mac clock is not clock
   synchronization, and setting the alarm must not silently synchronize the Evo.
3. Preserve slot 2's current sound mode, trigger, frequency bytes and volume.
   The earlier live baseline is mode 2, trigger 1, frequency `00 00`, volume 50.
   Those are existing device bytes, not newly invented sound defaults. No volume
   100 or named sound should be introduced from a reference implementation.
4. Set status 1, the selected near-future hour/minute, and mask 0. Read back with
   `42` and compare every field. A matching readback proves stored settings,
   not a successful firing.
5. Observe the real device at the scheduled time and query afterward. Record
   whether it rang, whether enabled cleared, and any other field changes.
   Sound or animation requires user observation; transport acknowledgement
   cannot supply that evidence.
6. Restore the saved slot 2 record and read all ten slots again. Compare every
   slot with baseline. If testing disable separately, send the current slot 2
   record with only status changed to 0, then verify readback. Call this disable,
   not deletion.

Even an unchanged exposed record may omit internal firmware metadata. Report the
restoration as exact equality of all exposed fields, without claiming restoration
of unobservable state. Preserve real packet fixtures and use `$MAC` in public
reports. A successful once test does not validate weekly repetition, finite-day
consumption, missed-time handling, or restart behavior.

## Observed slot 2 outcome

These observations came from the physical Evo on
2026-10-18, using local Europe/Paris time:

| Stage | Observation |
| --- | --- |
| Baseline | Slot 2 disabled, 00:00, mask 0, mode 2, trigger 1, frequency `00 00`, volume 50 |
| Set at 23:02:53 | Enabled slot 2 for 23:04, mask 0, preserving its sound settings; live readback matched every requested field |
| Other slots | All nine remained unchanged |
| Scheduled firing | User confirmed “it worked” |
| Read at 23:04:20 | Slot 2 automatically disabled; retained 23:04, mask 0 and its other settings |
| Restore | Original disabled 00:00 slot 2 record restored; all ten exposed records exactly matched baseline |

The observed request packet was:

```text
01 0d 00 43 02 01 17 04 00 02 01 00 00 32 a3 00 02
```

This establishes the near-future no-days firing and automatic disable on this
Evo. It does not establish a repeat-week observation or restart persistence.
Automated tests use this independently observed packet and the earlier pinned
reference golden, without labelling synthetic boundary cases as captures.

The [exposed-field fixture](fixtures/evo-alarm-write-once.json) records slot 2
before setting, after setting, after the due time and after restoration. The
device MAC is redacted as `$MAC`.

## Production CLI validation

The finished CLI was separately tested on slot 2 at 23:11 local time:

1. `alarm set 2 --time 23:13 --device main-evo --json` returned `sent`, with live
   readback showing enabled at 23:13 and all preserved sound settings unchanged.
2. `alarm disable 2 --device main-evo --json` immediately changed the enabled
   slot to disabled, retaining its time and other fields. Live readback matched.
3. The original disabled 00:00 record was restored. All ten exposed records
   exactly matched the pre-test snapshot.

This test disabled the second alarm before its due time; no second firing was
intended. It establishes the explicit enabled-to-disabled stored-state change,
not an independently observed long-term absence of firing. The CLI's set and
disable results both come from fresh readback, not local command history.

`swift test`: 64 tests pass, including protocol fixtures, invalid schedules,
recurrence aliases, shared CLI/REPL packets, and snapshot/readback failures.
The release CLI build passes. Finite weekdays remain open as described in the
[follow-up](evo-finite-weekday-follow-up.md).
