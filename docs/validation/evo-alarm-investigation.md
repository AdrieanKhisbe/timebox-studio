# Evo alarm investigation

Tracked by [AdrieanKhisbe/timebox-studio#9](https://github.com/AdrieanKhisbe/timebox-studio/issues/9).
Investigated 2026-10-18. **Source evidence only; hardware validation remains open.**

The two reference encoders agree on alarm payload bytes. They do not establish
the requested distinction between finite weekday schedules and weekly recurrence.
There is insufficient evidence to release `alarm set`, `alarm disable`, or live
listing as supported Evo operations. A successful Bluetooth write would not close
that gap. No device alarms were changed during this investigation.

## Sources and reproducibility

References are pinned, rather than following a moving default branch:

- [hass alarm encoder](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py#L676-L713),
  [Timebox model](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timebox.py),
  [golden input](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/tests/cases.py#L98-L101),
  and [golden packet](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/tests/goldens/Timebox/show_alarm.txt).
- [esp32 alarm encoder](https://github.com/d03n3rfr1tz3/esp32-divoom/blob/b69b1bd7d84c306202beca98ab90549f36d590b9/components/divoom/divoom.cpp#L854-L906)
  and [its alarm documentation](https://github.com/d03n3rfr1tz3/esp32-divoom/blob/b69b1bd7d84c306202beca98ab90549f36d590b9/README.md#mode-alarm).
  The documentation leaves device slots and mode meanings to the phone app;
  neither is an Evo capability declaration.
- [Divoom's submitted Evo manual](https://fcc.report/FCC-ID/A8I-TIMEBOX-EVO/4128242.pdf)
  describes a single **manual** alarm and further app options. This does not
  establish the number or numbering of programmable slots.

The previously documented `apk/` and `/tmp/divoom_src` decompile paths were absent
in the inspected environment. No official-app packet capture or alarm model was
available, and no such evidence is implied by the reference files below.

Reproduce the six cases without Bluetooth or third-party Python packages
(Python 3.10+ and a C++ compiler are required):

```sh
curl -L -o /tmp/alarm-hass.py https://raw.githubusercontent.com/d03n3rfr1tz3/hass-divoom/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py
curl -L -o /tmp/alarm-esp32.cpp https://raw.githubusercontent.com/d03n3rfr1tz3/esp32-divoom/b69b1bd7d84c306202beca98ab90549f36d590b9/components/divoom/divoom.cpp
python3 scripts/research/verify-alarm-references.py --hass-source /tmp/alarm-hass.py --esp32-source /tmp/alarm-esp32.cpp
swift test --filter AlarmReferenceFramingTests
```

The script checks both downloaded file hashes, extracts only reviewed encoding
methods, substitutes a byte collector for transport, and compares both encoders
with [the fixtures](fixtures/evo-alarm-reference.json). The Swift test independently
checks the repository's existing generic Evo framing against those packets.
The reference files are not copied into this repository. Neither check validates
an alarm's behavior on firmware.

## Capability table

Offsets below are **payload offsets**, beginning with opcode `43`; full packet
framing remains `01 LEN(le16) PAYLOAD SUM16(le16) 02`.

| Capability | Source evidence | Evo hardware evidence / release decision |
| --- | --- | --- |
| Set payload | `43 slot enabled hour minute weekdays alarmMode triggerMode freq0 freq1 volume` | Not tested; no supported command yet |
| Slot | One byte at offset 1; upstream golden uses 1 | Valid slot count and zero/one-based numbering unknown |
| Enable / disable | Offset 2 is 1 when time supplied, otherwise 0; omitted time also zeros hour/minute | Disable effect, retained fields and persistence unknown; do not call deletion |
| Time | Hour and minute at offsets 3–4 | Resolution, device-local next occurrence and boundary behavior unverified |
| Weekdays | Offset 5: Sun=1, Mon=2, Tue=4, Wed=8, Thu=16, Fri=32, Sat=64 | Day mapping not observed on Evo |
| No weekdays | Mask 0 in reference bytes | One-shot versus other firmware interpretation unknown |
| Finite selected weekdays | No independently identified recurrence parameter | Not established; must remain blocked |
| Weekly recurrence | Weekday mask exists; mode bytes are forwarded | Not established; do not assign meaning to `triggerMode` or bit `80` |
| Sound / volume | Mode bytes 6–7, frequency bytes 8–9, volume byte 10; hass defaults volume to 100 | Safe defaults, supported names/ranges and audible result unknown |
| Live list | No list operation or alarm-response parser established by these sources | Query opcode, response schema, slot enumeration and timeout behavior unknown |
| Restart | No observed run here | Firing, auto-disable, weekday consumption and persistence unknown |

The upstream golden uses slot 1, 07:30, Monday/Wednesday/Friday, raw mode bytes
1/1, frequency 101.1, and volume 80. It is reproduced byte for byte:

```text
01 0d 00 43 01 01 07 1e 2a 01 01 0b 0a 50 08 01 02
```

The other fixtures isolate absent/one/multiple/all weekdays and the reference's
disabled shape. Their explicit zero mode/volume values are laboratory inputs,
**not a recommendation or a claim of silent operation**. There is intentionally
no fixture labelled “once” or “recurring”: those behaviors have not been proven.

## Evidence still needed

First identify the Evo firmware and app version, an explicitly unused slot, and
its prior state. Do not infer a free slot from a name or from a guessed range.
If prior bytes cannot be read, document exactly what can be restored through
the official app before writing anything. Keep MAC addresses as `$MAC` in reports.

Capture app-originated requests and replies while changing one property at a
time. Preserve raw bytes and timestamps, not just app screenshots:

| Case | Comparison / observation required |
| --- | --- |
| No days, once | Next future local time; observe a firing and subsequent cessation |
| One day, once | Before and after today's requested time; establish next-week boundary |
| Multiple days, once | Each selected next weekday fires once, including a set spanning a rolling week; none repeats the following week |
| Same days, recurring | Compare exact packet fields with once; observe weekly repetition |
| Disable | Capture disable, query afterward, observe no scheduled firing; distinguish disable from deletion |
| Restart | Repeat pending and consumed cases around device restart |
| Listing | Capture app refresh, requests, complete framed replies and response-to-slot matching; enumerate actual supported slots |
| Sound | App labels, explicit values and verified low-volume behavior; do not copy the reference's loud default |

Read-only discovery does not answer these scheduling questions. Captures alone
can establish field encoding but not cessation or recurrence after firing; those
observations can remain tracked hardware validation. Changes to the device clock
must be explicit and recorded, never a side effect of setting an alarm.

## Decision for T9

[AdrieanKhisbe/timebox-studio#10](https://github.com/AdrieanKhisbe/timebox-studio/issues/10)
remains blocked on the evidence above. Its current spec requires a validated
slot range and observed disable operation as well as schedule semantics; even a
subset implementation would currently guess at those requirements. No typed
alarm API, CLI or REPL handler is added in this investigation.

If captures establish ordinary one-shot and weekly schedules but cannot establish
native finite weekday schedules, the concrete interface revision to seek approval
for is:

```sh
timeboxctl alarm set SLOT --time 07:30
timeboxctl alarm set SLOT --time 07:30 --days mon,tue --recurring
timeboxctl alarm disable SLOT
```

Keep `--recurrent` as the alias, require days for recurrence, and explicitly reject
`--days` without recurrence as an unsupported schedule. This is a **proposal**,
not an accepted spec change. It must not be implemented merely because these
reference bytes exist. If even those semantics cannot be established, keep the
whole write interface blocked. Do not silently convert finite days to weekly
recurrence, run a host scheduler, consume additional slots, or substitute local
history for the live listing required by
[AdrieanKhisbe/timebox-studio#12](https://github.com/AdrieanKhisbe/timebox-studio/issues/12).
