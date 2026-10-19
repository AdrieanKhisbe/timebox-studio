# Original Timebox Mini alarms and timers: prototype source findings

Date2026-10-19. Source-only; no hardware connections, writes or clock changes.
No changes to frozen feature/dev branches. Calculated fixtures below are not
hardware captures or claims of successful Mini behavior.

## Pinned primary implementations

- [hass-divoom Mini subclass](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py)
  explicitly selects11pixels and escaping, implements Mini-specific alarms and
  stopwatch selector, and explicitly rejects countdown.
- [Shared command map/framing](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py)
  maps setalarm43 and setview45. Do not substitute its generic alarm schema or
  generic72 tools for the Mini overrides.
- [Original Mini protocol](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/doc/protocol.md)
  documents `45 06 00` as showing the stopwatch, separately from scoreboard4507.
- [mathoudebine Mini source](https://github.com/mathoudebine/homeassistant-timebox-mini/blob/7cdbe2d096890a47c5710abae06948e66900be50/custom_components/timebox_mini/timebox.py)
  has display/framing support, but no alarm/stopwatch/countdown API located. It
  supplies no independent alarm readback or timer duration semantics.

## Alarm scope and preservation gate

Mini-specific `show_alarm` ignores number, weekdays, mode, trigger, frequency and
volume parameters. It sends `43 HH MM 01 FF` when a time exists, otherwise
`43 00 00 01 00`. The third data byte is a constant01; its meaning is not
established by that source. FF/00 are enabled/disabled based on the implementation,
not a proven weekday/recurrence mask. There is no justified slot index, so the Evo
slot2 instruction cannot safely be applied to this layout. It may address one
legacy alarm; the hardware semantics remain to be observed. Disable writes zeros
for time and therefore cannot be described as preserving the previous time.

Actual APK3.8.40 (SHA256d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81)
`DeviceFunction.DeviceTypeEnum.setDeviceMode` uses TIMEBOX_MIN→MiniUiArch,
OldMode and AlarmSupport (lines817–834 in inspected output). Generic
`CmdManager.k` sends42; generic receiveu.h370–376 dispatches a successful42
response to the modern alarm parser. This grounds a **read-only candidate**,
but not a Mini-specific response schema or ten-slot assumption. No inspected
Mini-specific source provides a verified readback mapping. A prototype may
capture the entire fresh escaped42 response and report unknown, without writing
alarms or assuming zero/disabled on timeout. Only an independently established
original configuration (official app/manual backup or decoded verified readback)
can permit an alarm test with restoration; do not overwrite an unknown existing
alarm. Do not automatically synchronize the device clock. A relative host target
of now+2minutes is meaningful only after checking the Mini clock separately.

## Stopwatch and countdown scope

Mini-specific hass code sends `45 06 VALUE`, defaultVALUE2. OriginalMini docs
independently confirm VALUE0 enters/shows stopwatch. The inspected current APK
StopwatchFragment uses actions0stop,1start,2reset, but goes through generic
ToolModel/CmdManager paths (72) rather than proving those meanings for Mini4506.
Thus treat450601/02 as source-backed Mini selector variants whose visible
start/reset semantics need explicit validation, not already proven action names.
Do not relabel ordinary4506 stopwatch as a countdown. Mini subclass explicitly
marks countdown unsupported; no source-grounded duration-bearing Mini countdown
packet was found. Sending Evo7203 packets as a Mini countdown is unjustified.

## Calculated escaped wire fixtures

Length/checksum are computed on the unescaped body; interior bytes01/02/03 become
0304/0305/0306. Delimiters stay01/02. All fixtures are offline calculations.

| Operation | Unescaped command payload | Escaped complete wire frame |
| --- | --- | --- |
| alarm-read-candidate | `42` | `0103060042450002` |
| alarm-set-07:30-reference | `43071E01FF` | `01070043071E0304FF6F030402` |
| alarm-disable-reference | `4300000100` | `0107004300000304004B0002` |
| stopwatch-show/reference0 | `450600` | `010500450600500002` |
| stopwatch-value1-candidate | `450601` | `01050045060304510002` |
| stopwatch-value2-candidate | `450602` | `01050045060305520002` |

## Recommended bounded prototype order

1. Capture read-only42 once on fresh exclusiveMini connection; retain unknown
   bytes/timeout, validate escaping/checksum, do not assume modern slots.
2. Show stopwatch450600, then only explicitly announced450601/02 observations;
   record visible action, reconnect/overlay effects, and leave user-controlled
   stop/reset available without changing clock/alarms.
3. Alarm writes remain gated on a backed-up known legacy alarm state and explicit
   agreement to replace that alarm. Keep a literal original restoration payload;
   do not silently write zeros as restoration.
4. Report countdown as unsupported research outcome until a Mini-specific duration
   protocol is established. Host-timed animation is a different feature.

Scratch-source SHA256 checksums:
- `mini-alarm-hass-timeboxmini.py`: `e8cf404b66cb1692bbe774109cd61105e370c08aa3c6f7e4c1c11a77f666fd74`
- `mini-alarm-hass-divoom.py`: `3ec17896fb782bb3978ef38df3a68773ef6db3fb5f490ea9f88672fadd2f2fc6`
- `mini-alarm-mathoudebine.py`: `422e39154c78220655f5c5d0fe0c5e43daf03da49b5708018545f7be0831d687`
- `mini-alarm-jbfuzier-protocol.md`: `699a6a8cf6a3a9503fba67c9e342215196a5fdcac2ea4f8aaf12370fcd412f2a`

## Live follow-up

Current APK OldMode parser explicitly returns3×10byte alarm records. AlarmViewModel.a and CmdManager.y0 send slot plus all9fields under43. Mini read42 captured30data bytes with IDs0,1,2; details in observations.json. The older short alarm implementation is not used for writes in this prototype.
