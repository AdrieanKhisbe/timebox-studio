# Original Timebox: legacy11 compatibility

Tracks AdrieanKhisbe/timebox-studio#20. Validation date: 2026-11-01.
The tested original Timebox is distinct from Timebox Mini and MiniToo.

## Product, protocol and transport

`timebox`, `mini` and `evo` identify products. Original Timebox and Mini use
`legacy11` framing/RGB444; Evo uses `evo16`. Bluetooth Classic RFCOMM and BLE
are transports. Product names, MAC prefixes and channel numbers are not used
to guess model identity; use `--model timebox` or a saved `model: timebox`.
Existing Mini model values and public Mini encoder names remain compatible.

```sh
timeboxctl status --device old-timebox
timeboxctl display clock --device old-timebox
timeboxctl image art.png --device old-timebox
timeboxctl repl --device old-timebox
```

The original shares the legacy encoder, query/response dialect, 11x11 image
conversion and model-specific CLI/REPL routing. Three alarm records were read
without writing. Native animation, streamed text, RTC synchronization, stopwatch
and alarm writes share the protocol implementation; this report does not claim
fresh original-device acceptance for those operations. Native countdown and Evo
display styles/design tabs remain unsupported for legacy11 models.

## Hardware evidence

- Unpaired `TimeBox-light` was discovered over BLE and connected without pairing.
  Device Information reported Anyka/1052C. Direct OldMode frames sent to UART RX
  `49535343-8841-43F4-A8D4-ECBE34729BB3` worked without an RCSP wrapper.
- Settings opcode46 returned the same 23-byte layout accepted by the Mini decoder.
  Baseline was clock mode0, system brightness20, light brightness100.
- The user confirmed a visible brightness increase20 to80, then the complete
  orientation image and yellow smiley. Image uploads used acknowledged20-byte
  ATT chunks and received `01 06 00 04 44 55 00 A3 00 02`.
- After the previously connected host was disconnected, macOS showed paired,
  connected `TimeBox-audio`. SDP advertised Serial Port1 on RFCOMM channel4.
  Production Classic settings and three-slot alarm reads succeeded; alarm
  settings were not modified.
- All23 baseline settings bytes were restored after the BLE display checks.
- The rebuilt release CLI then used `--model timebox` over Classic for status,
  full-profile clock selection and status again. Both reads matched all23 bytes
  exactly. Named targeting was verified again after saving `model: timebox`;
  `main-evo` remained the default device.

BLE results used a private diagnostic harness. They do not enable production
legacy11 BLE/iOS or UUID target configuration; the normal CLI path here is
paired Classic RFCOMM. No copyrighted firmware/app artifacts are included.

## Clock-profile regression

The short clock selector `45 00 00` changed raw settings bytes10-12 from
`00 3E E0` to `4A 00 00`: the firmware consumed the short frame's checksum
as missing RGB data. Returning to clock mode alone is therefore insufficient.

The complete original profile is `45 00 FORMAT R G B`, using settings byte9
and bytes10-12. The captured restoration frame was:

```text
01 08 00 45 00 00 00 3E E0 6B 03 04 02
```

A fresh query verified that this restored all23 bytes exactly. Bare clock
selection now requires a fresh model-specific status read for both original
Timebox and Mini. Unknown format values, incomplete/extended layouts and failed
reads reject before control writes; no profile defaults are invented. The
low-level encoder requires a prepared full profile instead of emitting a short
selector. Clock time and alarms are not written by this operation.

The response/clock frames in `OriginalTimeboxTests` are literal hardware captures,
independent of the expected production encoder output. Automated checks also
exercise fragmentation, config preservation, actual product identity in results,
REPL reconnection/channel retention, shared animation metadata and rejected Evo
commands before I/O. Historical Mini reports describe the former short selector;
their visual clock acceptance did not establish stored-RGB preservation.
