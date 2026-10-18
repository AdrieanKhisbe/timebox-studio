# Finite weekday alarm follow-up

Open requirement of [AdrieanKhisbe/timebox-studio#10](https://github.com/AdrieanKhisbe/timebox-studio/issues/10).
Investigated 2026-10-18 after the successful near-future once test. The user chose
to **keep finite weekdays blocked and investigate further**. This document does
not change the original requirement or claim the feature is impossible.

Desired finite semantics remain: a no-recurrence alarm selecting Monday and
Tuesday fires at each day's next requested local time, then stops. A weekly mask
does not satisfy that behavior. The verified mask-zero firing and automatic
disable do not establish finite multi-day support.

## Additional source checks

- The [manufacturer's complete public catalogue](https://docin.divoom-gz.com/server/index.php?s=/api/item/info&item_id=5)
  places pages 246–254 under Bluetooth / alarm memorial, covering alarm get/set,
  artwork, memorials, preview and volume. No separate finite-alarm operation is
  identified in that inspected catalogue. This is a statement about published
  coverage, not proof of firmware absence.
- [Alarm setter page 247](https://docin.divoom-gz.com/web/#/5/247) defines a weekly
  day mask and the ten exposed fields. The
  [archived app builder](https://github.com/DavidVentura/divoom/blob/0cb77c83503012fb7f5c8b7d4a52f8eeab398e66/decompiled-sources/CmdManager.java#L1067-L1094)
  serializes those ten fields without an independently named recurrence
  parameter. Neither establishes how bit 7 should behave.
- The [app 3.8.40 surface inventory](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/docs/android-surface.json)
  identifies the Bluetooth `view/fragment/alarm/view/AlarmWeekAdapter.java` UI
  strings as “Never” and seven weekday names. The inventory includes hashes of
  the original classes and APK, but not their complete control flow. It does
  not show a separate finite-multiple-days control or a numeric sound/trigger
  mapping. Inferring the full firmware state machine from those strings would
  exceed the evidence.
- Adjacent [time management page 256](https://docin.divoom-gz.com/web/#/5/256)
  ([original JSON](https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=256))
  describes `56` records with start/end times and a cycle mode whose semantics
  depend on the device. [Page 259](https://docin.divoom-gz.com/web/#/5/259)
  describes the global `57` control/status flag. These concern a different time
  management subsystem; they do not establish finite Evo alarm schedules. No
  `56`/`57` command was sent as part of this follow-up.

The code searches and source inspection found no grounded mapping that assigns
finite weekday consumption to bit `80`, sound mode, or trigger mode. That result
is insufficient to assert impossibility. Those fields must remain unmodified
unless their meaning is independently established.

## What would resolve the gap

The next useful evidence is the actual Bluetooth alarm editor/model control
flow from the documented APK revision, or an app-originated capture demonstrating
the requested finite multi-day behavior on an Evo. Trace the weekday selection
through the model into the ten-byte builder. A screenshot containing weekday
choices alone cannot distinguish finite consumption from weekly repetition.

If such a control exists, capture identical weekday selections with finite and
recurring intent, then identify the exact differing bytes. Validate behavior on
one explicitly authorized unused slot across each selected next weekday and the
following week, including a set crossing the current week's boundary. Restart
and already-passed-today cases need their own observations. Do not change the
device clock or extend hardware-write authorization implicitly to accelerate
these tests.

Until that evidence exists, retain the dedicated `unsupportedFiniteWeekdays`
error for days supplied without recurrence. Do not silently make the alarm
weekly, allocate extra slots, or add a host scheduler. Keep the issue's finite
requirement open while providing the independently established once and weekly
paths.
