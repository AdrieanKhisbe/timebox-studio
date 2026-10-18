# Timebox Evo Classic baseline — 2026-10-18

Issue: [AdrieanKhisbe/timebox-studio#2](https://github.com/AdrieanKhisbe/timebox-studio/issues/2).
Working branch: `fix/address-baseline-gitch`, based on
`3220cdf86bd707438140c1a6cd679c7bcc29caf9` (`update-setup`). This baseline excludes
the separate Mini prototype. The changes on this branch correct documentation,
CLI guidance and the asynchronous CLI wait; they add no new device command.

## Environment

| Item | Observed value |
| --- | --- |
| Host | macOS 15.8, build 24H23, arm64 |
| Developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Xcode | 26.2, build 17C52 |
| Swift | Apple Swift 6.2.3, swiftlang-6.2.3.3.21, clang-1700.6.3.2 |
| Swift target | arm64-apple-macosx15.0 |
| Device | Timebox Evo, confirmed available by the operator |
| Paired Bluetooth name | `TimeBox-Evo-audio-One` |
| Address used | `$MAC` |
| Firmware / hardware revision | Not obtained; no verified version query was used |
| Actual connected RFCOMM channel | 1, selected without a --channel override |

## Build and automated checks

Use full Xcode and the compiled executable directly for Bluetooth/TCC:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
swift build --configuration release --product timeboxctl
```

All three commands succeeded. `swift test` ran 12 XCTest cases with zero failures:
2 hex-parser, 2 pixel-frame and 8 packet/checksum/image-encoding tests. The separate
Swift Testing runner discovers zero additional tests. The existing tests verify
encoding; they are not Bluetooth integration or physical-display evidence.

The initial sandboxed build could not write the Clang/Swift caches and failed to
load the standard library. The same build succeeded with normal cache access;
this was an execution-environment restriction, not a source compilation failure.

CLI smoke checks `list --mock` and `inspect --mock` both returned exit code 0.
They exercised normal asynchronous dispatch without Bluetooth access. `git diff
--check` passed. The real SDP before/after check below covers the callback issue
that those mock paths do not reproduce.

## Discovery, SDP and the audio endpoint

```sh
.build/debug/timeboxctl list
.build/debug/timeboxctl inspect --address $MAC
```

`list` returned the Evo as paired and connected. Only the target device's details
are recorded here; unrelated paired devices are omitted.

Before the CLI wait fix, the exact inspect command exited 1 after eight seconds
with a Bluetooth scan-timeout error. The command actually awaited an SDP callback:
the top-level semaphore wait blocked its main-run-loop delivery. After replacing
the blocking wait with run-loop pumping, the same command exited 0 and reported
`SDP status: 0 / 0x00000000 (success)`.

The returned records included two Hands-Free entries on RFCOMM 1 (the same handle
`0x00010003`) and an unnamed RFCOMM 1 entry at handle `0x00010004`, plus L2CAP
records at PSM 0x0017 and 0x0019. This inspector does not print service-class UUIDs,
so this report does not infer which enumerated record matched UUID 0x1101.
Actual display commands independently connected on channel 1 and produced effects
confirmed by the operator.

The audio endpoint worked for Classic LED control. The CLI's former advice that
LED control required a light-side endpoint was incorrect and is corrected here.
The implicit candidate filter still excludes audio names; resolving that selection
mismatch belongs to [AdrieanKhisbe/timebox-studio#3](https://github.com/AdrieanKhisbe/timebox-studio/issues/3).
These baseline commands use an explicit address throughout.

## Physical acceptance

The operator explicitly authorized display/brightness tests on the paired Evo.
All commands used the existing native Classic path with automatic channel choice.

```sh
.build/debug/timeboxctl color FF0000 --brightness 30 --address $MAC --hold-ms 1500
.build/debug/timeboxctl repl --address $MAC
```

Inside the same REPL connection:

```text
brightness 20
brightness 80
color 00FF00 30
quit
```

Then, as separate one-shot commands:

```sh
.build/debug/timeboxctl brightness 60 --address $MAC --hold-ms 1500
.build/debug/timeboxctl image docs/validation/fixtures/evo-orientation.png --address $MAC --hold-ms 1500
```

| Check | Transmission / execution evidence | Physical observation |
| --- | --- | --- |
| Solid red | One-shot color wrote 17 bytes on channel 1; exit 0 | Operator confirmed red appeared |
| Brightness | REPL wrote 8 bytes each for 20% and 80%; one-shot 60% wrote 8 bytes, exit 0 | Operator confirmed the visible 20% → 80% change; the separate 60% level was not independently assessed |
| Persistent REPL | One connection message, three successful writes, then explicit disconnect/exit 0 | Operator confirmed red brightness changes followed by green |
| Static image | One-shot image wrote 132 bytes on channel 1; exit 0 | Operator confirmed the expected orientation and colors |

The operator's response was “Oui, tout est apparu comme décrit” to the explicit
red, 20% → 80%, green and orientation-pattern checklist. This is separate evidence
from the transport's write-complete messages.

The included [orientation fixture](fixtures/evo-orientation.png) is a native 16×16
RGB PNG: white top-left pixel, red top edge, green left edge, yellow diagonal,
blue bottom-right pixel and black elsewhere. It contains six colors. It checks
basic row/column orientation and static-file conversion; it is not an exhaustive
palette, alpha, resize, animation or 256-color/MTU test.

## Scope and result

Local build/test/release checks, paired discovery, successful SDP inspection,
visible color/brightness/static-image behavior and persistent REPL operation are
validated on this Evo and macOS configuration. The branch is ready for code review.

Historical raw BLE diagnostic failures must not be generalized to RCSP-over-BLE:
the iOS library has a separate RCSP transport. This session validates Classic
only; it does not revalidate iOS, other firmware, automatic name/default routing,
Mini compatibility or the capabilities in later tickets. No firmware version or
live state readback is claimed.
