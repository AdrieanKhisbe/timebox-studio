# Original Mini clock synchronization

Tracks [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20)
and [AdrieanKhisbe/timebox-studio#15](https://github.com/AdrieanKhisbe/timebox-studio/issues/15).
Date: 2026-10-19. Device: AKTBR (`$MAC`), original Mini, Classic RFCOMM channel4
resolved by SDP. Model selected explicitly; no automatic identification claim.

```sh
timeboxctl time sync --address "$MAC" --model mini
timeboxctl display clock --address "$MAC" --model mini
```

The same commands work in a persistent REPL. Library callers use
`TimeboxClient(model: .mini).synchronizeClock(at:timeZone:)`.
One Gregorian local snapshot supplies every field, including the weekday;
model-specific re-encoding does not capture a second instant. The device receives
no timezone identifier or ongoing DST maintenance. The Mac clock is unchanged.

## Source evidence

The current official Android app3.8.40 `CmdManager.X0()` builds opcode18 followed
by `year%100, year/100, month, day, hour, minute, second, weekday`, with Sunday0.
The Mini profile selects OldMode, escaping interior01/02/03 as0304/0305/0306
after the unescaped length and checksum have been calculated. APK SHA256:
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`.
No copyrighted decompiled source is distributed.

Older primary implementations differ. The pinned
[mathoudebine setter](https://github.com/mathoudebine/homeassistant-timebox-mini/blob/7cdbe2d096890a47c5710abae06948e66900be50/custom_components/timebox_mini/__init__.py)
omits the final weekday byte. The pinned
[jbfuzier setter](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/package/timebox.py)
includes a constant00; its
[protocol notes](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/doc/protocol.md)
leave that field uncertain. Production follows the current official app's
model-specific route and uses the actual weekday rather than the older constant.

No safe Mini RTC getter was established. In particular, BD2E is a device request
for host time whose handler sends the setter; it must not be treated as a safe
clock-read probe. Structured CLI success says `sent`, not verified readback.

## Automated verification

Independent source-derived wire fixtures cover Sunday, Monday and a century leap
day, including reserved bytes in calendar fields. The Monday2026-03-02
01:02:03 fixture is `010B00181A140306030503040305030603045D0002`.
These are calculated fixtures, not radio captures. CLI JSON/YAML, REPL and library
tests verify model framing, a single captured instant, and retained unsupported
capability guards. Existing Gregorian timezone/date-boundary tests remain in place.
The full suite passed154tests; the release CLI also built successfully.

## Hardware acceptance

Before synchronization, a fresh production alarm query found all three slots
disabled with the previously restored settings. A release-build persistent REPL
on channel4 sent `time sync` (17bytes) and `display clock` (10bytes).
The subsequent host observation was2026-10-19 22:57:03 CEST; the exact transmitted
calendar payload was not captured. The user confirmed the displayed time matched
local time after the write.
Date and weekday are hidden by this display and have not been independently
verified on the device. No recurring-alarm event or power-cycle persistence
claim follows from a clock write.

## Selected-weekday alarm follow-up

After the visual clock check, production `alarm set 2 --time 23:06 --days mon`
programmed the upcoming Monday event. Its fresh readback matched, including mask02;
all fields in slots0 and1 remained unchanged. An earlier23:00 schedule was
replaced after noticing that time had already passed during the first attempt.
The user confirmed the23:06 alarm triggered. This establishes a selected-weekday
trigger on this Mini, not an independently observed week-later repetition.

The original slot2 record was restored with the previously captured, model-correct
full-record packet. A fresh production alarm query confirmed every baseline field:
all three slots disabled at00:00, mask0, sound0, trigger1, frequency[0,0], volume50.
No test alarm remains enabled. The corrected device clock was intentionally kept.
