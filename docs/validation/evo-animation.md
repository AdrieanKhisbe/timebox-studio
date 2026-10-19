# Evo animation hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#14](https://github.com/AdrieanKhisbe/timebox-studio/issues/14).

The parent exclusively operated `main-evo` / `$MAC`, SDP RFCOMM channel 1. The implementation agent prepared an original standard-library-generated input and performed mock dry runs only.

Input: `red-green-500ms.gif`, 473 bytes, SHA256 `bd2505ffd8ad76bf1166e952d6f814f22f45b29c110bae0fadd2b2572fdef1c7`; 16×16, two full opaque frames: red `(255,0,0)`, then green `(0,255,0)`, each 500ms. Source loop metadata is infinite. No external asset, resizing or lossy adaptation was required. Encoder metadata: two effective frames, 1000ms total, 84 stream bytes, one packet, 94 wire bytes.

The same media branch's `.build/debug/timeboxctl animation ... --device main-evo --json` completed transmission. Asked whether red and green alternated at roughly 500ms each and repeated, the user answered “yep”. This confirms visible order, approximate cadence and repetition for this small debug upload, not measured timing precision or a finite-loop API.

## Release connection failure remains unresolved

Before the successful debug attempt, the optimized release binary failed to open RFCOMM1 before transmitting, with timeout `-536870186`, on three attempts including after the user's power cycle and closure of the phone app. A debug status query from the response branch then succeeded, followed by the successful debug animation on this media branch.

Inspection found debug SwiftPM's explicit ad-hoc signing step binds the four-entry Info.plist and bundle identifier, whereas release was only linker-signed with Info.plist unbound. Both binaries contain the embedded plist. A scratch copy of the optimized release was ordinary ad-hoc re-signed without debug entitlements; its machine-code/plist section hashes were unchanged and signature validation passed. **The parent tested that variant and it still timed out before transmission.** Plain re-signing is therefore insufficient; no signing fix or optimization root cause is claimed. Hardware access for further diagnosis remains parent-owned.

This connection failure is separate from a packet rendering rejection: it occurs before TX, while the debug packet demonstrably renders. Release compilation and mock transmission do not validate live Bluetooth access. The feature is not release-hardware validated.

Pending hardware coverage: exact playback timing, measured looping, source disposal/transparency and fit/fill/stretch variants, adaptation, input capacity boundaries, state after interrupted uploads and power-cycle persistence. The [text acceptance](evo-text.md) separately covers a 13-packet upload. No raw notification capture, exact attempt timestamps or exhaustive memory measurement were retained.
