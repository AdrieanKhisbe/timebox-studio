# Mini scrolling text over a persistent host connection

Tracks [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20)
and [AdrieanKhisbe/timebox-studio#18](https://github.com/AdrieanKhisbe/timebox-studio/issues/18).
The user explicitly selected an opt-in `--stream` interface on 2026-10-19.

## Source and design

The original Mini controller's pinned
[`show_text`](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/package/timebox.py)
renders horizontal slices and sends each as a static image with a host delay.
Its separate `show_text2` uses dynamic frames and documents a different speed
limit. This provides a source-grounded host-streaming route, independently of
the native animation buffer. Our static RGB444 encoding is already physically
validated on AKTBR; no new opcode or storage operation is introduced.

The production implementation rasterizes every supplied glyph with the system
fixed-pitch font at 9px, centers it in an 11×11 viewport, and keeps all one-pixel
positions from blank entry through blank exit. Unsupported glyphs or oversized
text fail before connection. It pre-encodes every escaped static-image packet.
There is no animation adaptation, frame thinning, glyph fallback or truncation.

`text --stream` is one pass at a target 100ms per position. Its monotonic pacing
subtracts write time and extends playback if writes are late. It never skips
frames to catch up. Normal CLI closes after the last frame's hold; REPL retains
its current connection. A failed write stops immediately without replay.
Library task cancellation stops subsequent writes while preserving caller-owned
connection lifetime. Native animation limits are unchanged.

Examples, with a configured Mini or explicit address:

```sh
timeboxctl text "Hello Mini" --stream --device mini --json
timeboxctl repl --address "$MAC" --model mini
# Inside the REPL:
text --stream "Hello Mini"
```

The process must remain running and connected. Ctrl-C ends the CLI. There is no
native repeat or offline continuation. Completion output means the host finished
sending, not verified pixel readback. Text is white on black; a final blank frame
clears the scroll. The Mini may show its Bluetooth icon after disconnection.

## Automated and physical evidence

Tests exercise upright 11×11 rasterization, every one-pixel position beyond the
native buffer limit, blank entry/exit, exact static-packet parity, CLI JSON/YAML,
slow-write pacing, no retry or false success on partial failure, current REPL
target/model changes, library cancellation and preservation of native Evo text.

The full suite passed 171 tests and the release CLI built successfully. A release
mock invocation for `Hello Mini` reports Menlo-Regular at 9px, 67 frames, a 6700ms
target duration and 12940 encoded wire bytes. These are planned/simulated values,
not radio observations.

Two initial connection attempts to AKTBR (`$MAC`) resolved channel4 but timed out
before writes; the user then confirmed the device had been off and powered it on.
The next release-build REPL connected on SDP-resolved channel4, with explicit
Mini model. After a five-second warning, `text --stream "Hello Mini"` completed
one pass on that persistent link. The user confirmed the complete message moved
right to left, upright and fully readable, then cleared. Its prepared plan was
the same 67 frames / 12940 wire bytes reported above; no radio packet capture or
measured timing was taken. No native repeat, exact cadence, throughput or
persistence claim follows from this single pass.

The Mini's clock display was selected afterward and the connection closed.
No clock time or alarm settings changed.
