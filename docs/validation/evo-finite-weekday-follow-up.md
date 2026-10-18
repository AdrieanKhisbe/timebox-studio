# Finite weekday alarm follow-up

Investigation for [AdrieanKhisbe/timebox-studio#10](https://github.com/AdrieanKhisbe/timebox-studio/issues/10).
Investigated 2026-10-18 after the successful near-future once test, then extended
by tracing the actual Android APK's editor, model and serializer. The user chose
to **keep finite weekdays blocked and investigate further**.

**Conclusion:** official app 3.8.40's inspected Bluetooth alarm editor and its
documented `43` command cannot represent finite multiple weekdays separately
from weekly repeat days. Its editor makes Never mutually exclusive with days;
its packer never sets bit 7. This establishes a limitation of that app-controlled
path, not impossibility of an undiscovered Evo firmware capability. The user subsequently simplified the interface: selected weekdays imply
weekly repetition, and no weekdays means once. Finite weekdays are outside
this revised interface.

Desired finite semantics remain: a no-recurrence alarm selecting Monday and
Tuesday fires at each day's next requested local time, then stops. A weekly mask
does not satisfy that behavior. The verified mask-zero firing and automatic
disable do not establish finite multi-day support.

## Actual APK acquisition and control flow

The [archive download page](https://apkpure.net/divoom-pixel-art-editor/com.divoom.Divoom/download)
identified package `com.divoom.Divoom`, version **3.8.40**, version code **640**.
The [observed raw download](https://d.apkpure.net/b/APK/com.divoom.Divoom?version=latest)
was acquired for offline inspection, never installed or run. Its SHA-256 is:

```text
d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81
```

This exactly matches the independent pinned
[app inventory's APK identity](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/docs/android-surface.json).
The publisher's actual app binary is the source inspected; APKPure is its
acquisition route. The `latest` URL is mutable, so a different hash must not be
treated as the same evidence. Divoom's current
[download landing](https://www.divoom.com/AppDownLoad) points Android to Google
Play; its historical APKPure links are commented out.

Inspection used official [JADX 1.5.6](https://github.com/skylot/jadx/releases/tag/v1.5.6)
and installed Homebrew OpenJDK 25.0.2. The JADX ZIP SHA-256 is
`545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974`.
All APK/decompiled code remains under `/private/tmp`, outside Git.

The following are exact local anchors from JADX 1.5.6 Java output. Methods are
named because decompiler versions and configuration can change line numbers:

| Class / method | Generated file anchor | Observed control flow |
| --- | --- | --- |
| `view.fragment.alarm.view.AlarmWeekAdapter`, constructor | `timebox-alarmweek.java:38` | Eight choices: Never, then Monday through Sunday. Never is initially selected alone. |
| Same, `g()` and `i(int)` | `timebox-alarmweek.java:104` and `:138` | Never clears all seven days. Any chosen day clears Never. Removing the last selected day selects Never again. |
| Same, `c()` | `timebox-alarmweek.java:59` | Exports only seven weekday flags; Never is excluded. |
| `view.fragment.alarm.AlarmAddFragment`, weekday listener in `standardLoad()` | `timebox-AlarmAddFragment.java:218` | Calls the selection method, exports flags, packs them, and overwrites `week[slot]`. |
| `view.fragment.alarm.model.AlarmViewModel.e(byte[])`, helper `f(...)` | `timebox-AlarmViewModel.java:74` and `:104` | Starts eight bits at zero and writes only lower-seven positions. Sunday maps to bit 0, Monday to bit 1, through Saturday bit 6. Bit 7 stays zero. |
| Same, `c(byte)` | `timebox-AlarmViewModel.java:52` | Unpacks exactly seven low bits for the UI; bit 7 is ignored. |
| `AlarmAddFragment`, save listener in `returnLoad()` | `timebox-AlarmAddFragment.java:195` | Sets selected time and enabled state, then calls the model sender. No separate recurring/finite flag is passed. |
| `AlarmViewModel.a(...)` | `timebox-AlarmViewModel.java:21` | Copies slot, enabled, time, week, sound mode, trigger, frequency and volume to the write model; invokes `CmdManager.y0`. Artwork uses a separate path. |
| `bluetooth.CmdManager.y0(...)` | `timebox-CmdManager.java:1841` | Serializes the ten documented bytes and wraps `SPP_SET_ALARM_TIME_SCENE`; no extra recurrence byte. |
| `bluetooth.alarm.AlarmGetInfo` and write record `p157r1.a` | `timebox-AlarmGetInfo.java:6` and `timebox-AlarmWriteRecord.java:4` | Expose the week byte and existing sound fields, without a separate finite/recurring property. |

Summary in pseudocode, without reproducing proprietary implementation:

```text
Never -> clear all selected days
weekday -> clear Never
last weekday removed -> select Never
week = pack seven days  // 0...127
send 43(slot, enabled, hour, minute, week, sound, trigger, frequency, volume)
```

**Bit-7 precision:** opening an existing alarm ignores bit 7 in the UI, but
opening alone does not overwrite its stored week byte. Editing any weekday
repacks and clears bit 7. Saving without a weekday change can forward the
original byte unchanged. None of this assigns a firmware meaning to bit 7.

The default `AlarmAddFragment` decompile emitted one error while still producing
the listeners. Its weekday listener was therefore independently inspected in
fallback instruction output with anonymous inlining disabled; that run completed
without errors and confirmed the selection/export/pack/store sequence. Adapter
and model packer were also cross-checked in fallback output without errors.

## Executed checks of extracted app methods

A scratch Java harness compiled the unchanged decompiled selection/reset/export
methods and mask pack/unpack methods, using only a backing byte array and a
no-op RecyclerView notification stub. It made no Android or Bluetooth calls.
These check app logic; they are not device captures:

| Sequence / input | Observed mask |
| --- | --- |
| Initial Never | `00` |
| Monday and Tuesday | `06` |
| Then Never | `00` |
| Select and deselect last weekday | `00` |
| Sunday | `01` |
| Decode `ff` to UI then repack | `7f` |
| All 128 seven-day combinations | Expected Sun-first masks; bit 7 always zero |

All checks passed. Scratch harness:
`/private/tmp/timebox-check-app-weekdays.py`; generated Java:
`/private/tmp/timebox-app-weekday-harness/WeekdayHarness.java`. Those files embed
extracted app methods and remain outside Git.

## Reproduction and integrity

Acquire the exact APK hash above. Example decompilation commands:

```sh
jadx -r --single-class com.divoom.Divoom.view.fragment.alarm.view.AlarmWeekAdapter --single-class-output /tmp/alarm-week.java /tmp/divoom-3.8.40.apk
jadx -r --single-class com.divoom.Divoom.view.fragment.alarm.model.AlarmViewModel --single-class-output /tmp/alarm-model.java /tmp/divoom-3.8.40.apk
jadx -r --no-inline-anonymous --decompilation-mode fallback --single-class 'com.divoom.Divoom.view.fragment.alarm.AlarmAddFragment$1' --single-class-output /tmp/alarm-listener-fallback.java /tmp/divoom-3.8.40.apk
```

For the inner listener JADX saves its parent; inspect the emitted
`AnonymousClass1.onItemClick` instruction listing. Normal-mode generated hashes:

| Class | SHA-256 |
| --- | --- |
| AlarmWeekAdapter | `1e49bca0d0a5f2a549bff9b9a48c8d2b645bf6ebf43e2e0bc0e2b34390e08da5` |
| AlarmViewModel | `11378b9b22e682e2424c28c12b3c8266fe03c258ec4a29a3098626e6ba526534` |
| AlarmAddFragment | `3d42dd9cb8164f72f58fe4b07b83fd9b8abe16a1329375c65942b2a442f38448` |
| CmdManager | `510037ffe270a6280d6f45837a242bf43f918262f261448f80e8843ffd9e9677` |
| AlarmGetInfo | `fb139d09f87797245824eaedfd1e3cc5ff90840f2e4283a5d48bcda731d6740d` |
| Write record p157r1.a | `d558fe8ec60ef686a1b7af9f8da7470bfb91e685057ccc34367262f17a51391f` |

Generated source hashes differ from the inventory because generated names/output
depend on decompiler configuration. The APK hash matches exactly. No app
installation, device write, or clock change was performed in this investigation.

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
- Related Ditoo Pro firmware work exposes alarm `days` only in `0...127`,
  with no separate recurrence option in its
  [Lua wrapper](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/native/lua-app/peripherals.c#L560-L591).
  Its [configuration writer](https://github.com/futpib/divoom-ditoo-pro-controller/blob/2dbb951c8e8d4ac48c8457228b3d4b50ecb74c80/native/lua-app/peripherals.c#L180-L223)
  preserves a 16-byte internal record, updates a timestamp at offsets 12–15,
  and calls the stock alarm rescheduler. The inspected published assembly
  extracts do not expose that scheduler's implementation. This concerns
  **Ditoo Pro firmware 306007**, so neither the wrapper's restriction nor the
  internal metadata establishes Evo finite-weekday behavior.

The code searches and source inspection found no grounded mapping that assigns
finite weekday consumption to bit `80`, sound mode, or trigger mode. That result
is insufficient to assert impossibility. Those fields must remain unmodified
unless their meaning is independently established.

## What would resolve the gap

The actual APK editor/model/serializer path has now been traced and all UI day
combinations checked. This closes the official-editor question for this version:
it has no separate finite-weekday encoding. Remaining useful evidence would be
a documented alternate firmware path, a different app revision demonstrating
one, or actual Evo capture/observation of finite consumption. Weekday choices
in a screenshot alone do not establish finite semantics.

If such a control exists, capture identical weekday selections with finite and
recurring intent, then identify the exact differing bytes. Validate behavior on
one explicitly authorized unused slot across each selected next weekday and the
following week, including a set crossing the current week's boundary. Restart
and already-passed-today cases need their own observations. Do not change the
device clock or extend hardware-write authorization implicitly to accelerate
these tests.

## Interface decision after investigation

The user accepted the limitation and requested removal of `--recurring` and
its `--recurrent` alias. `--days mon,tue` now directly means weekly repetition
on Monday and Tuesday; omitting `--days` means once. The Swift schedule likewise
accepts weekdays without a separate recurrence parameter. There is no finite
weekday mode, extra-slot allocation, or host scheduler in this interface.
The earlier rejection of weekdays without a recurrence flag is superseded by
this explicit decision, rather than silently changing the original semantics.
