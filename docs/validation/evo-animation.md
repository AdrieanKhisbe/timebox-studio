# Evo animation hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#14](https://github.com/AdrieanKhisbe/timebox-studio/issues/14).

The parent exclusively operated `main-evo` / `$MAC`, SDP RFCOMM channel 1. The implementation agent prepared an original standard-library-generated input and performed mock dry runs only.

Input: `red-green-500ms.gif`, 473 bytes, SHA256 `bd2505ffd8ad76bf1166e952d6f814f22f45b29c110bae0fadd2b2572fdef1c7`; 16×16, two full opaque frames: red `(255,0,0)`, then green `(0,255,0)`, each 500ms. Source loop metadata is infinite. No external asset, resizing or lossy adaptation was required. Encoder metadata: two effective frames, 1000ms total, 84 stream bytes, one packet, 94 wire bytes.

The same media branch's `.build/debug/timeboxctl animation ... --device main-evo --json` completed transmission. Asked whether red and green alternated at roughly 500ms each and repeated, the user answered “yep”. This confirms visible order, approximate cadence and repetition for this small debug upload, not measured timing precision or a finite-loop API.

## Release connection failure resolved as an execution restriction

Initial release attempts timed out opening RFCOMM1 before transmitting (`-536870186`), including after a power cycle and closure of the phone app. The early debug/release comparison did not control execution permissions, so it could not isolate build behavior.

The parent subsequently ran all variants through the same approved execution path: debug, untouched linker-signed release, release-Onone, optimized release with debug entitlement, then debug again. All connected on channel 1 in 0.12–0.31 seconds without a display payload. Most decisively, the **same original release binary, path, working directory and connect command** timed out after roughly 15 seconds under default sandbox execution, then connected in 0.147 seconds with `require_escalated` approval. The original release animation command also succeeded with that approved execution path: two frames, one packet, 94 bytes, 1000ms total, no adaptation.

This establishes the execution sandbox as the blocker for those attempts. The debug/release signing differences exist, but ordinary re-signing was insufficient and neither signing nor optimization changes were necessary for success. No permission database reset, sandbox-profile bypass, new Bluetooth entitlement or transport source change was performed. See [controlled execution comparison](cli-bluetooth-execution.md).

Visible order, approximate cadence and repetition were human-confirmed for the earlier debug upload. The subsequent original release upload has successful live transmission evidence; it did not receive a separate new human timing observation. `sent` still means transmission rather than a device readback assertion.

Pending hardware coverage: exact playback timing, measured looping, source disposal/transparency and fit/fill/stretch variants, adaptation, input capacity boundaries, state after interrupted uploads and power-cycle persistence. The [text acceptance](evo-text.md) separately covers a 13-packet upload. No raw notification capture, exact attempt timestamps or exhaustive memory measurement were retained.
