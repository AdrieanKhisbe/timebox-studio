# Evo countdown hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#16](https://github.com/AdrieanKhisbe/timebox-studio/issues/16).

The parent agent exclusively controlled the hardware session. This report records its supplied observations; the implementation agent performed no device access. Logical target: `main-evo`, Bluetooth address `$MAC`, RFCOMM channel 1. No exact wall-clock timestamps, raw packet capture, notification trace or measured timing accuracy were recorded.

| Attempt | Transport evidence | Human observation | Acceptance |
| --- | --- | --- | --- |
| Repeated `countdown start 00:05` attempts | Standalone CLI sends; no retained per-attempt byte capture | Asked about visible countdown to zero and completion sound; user answered “both yes” | Visible natural completion and completion sound confirmed |
| `countdown start 00:30`, followed by stop attempts | Standalone commands | Initial acknowledgment followed by a statement that starting had not been seen | Ambiguous; not used as early-stop acceptance |
| Fresh `countdown start 02:00` | CLI reported 11 bytes sent | User confirmed visible ticking | Start confirmed |
| `countdown stop` while the longer countdown was running | CLI reported 11 bytes sent | User said “it stopped with an animation” | Stop before zero and a stop animation confirmed |

These observations support the implemented app-derived `72 03 01 minutes seconds` start and `72 03 00 00 00` stop semantics despite the reversed manufacturer control prose. The packet bodies are established by encoder fixtures; the hardware session retained byte counts rather than a fresh raw capture.

Each standalone CLI command disconnects after its send/hold period. The longer countdown remained observable after that command returned, and stop worked through a later connection. This is evidence of operation across these immediate command disconnects, not proof of persistence across power cycles, arbitrary reconnect delays, display-channel changes or restarts.

Not validated: maximum duration, 59:59 boundary on hardware, repeated start semantics, reset/pause/resume, sound selection, exact countdown rate, restart behavior, or channel-switch persistence. No separate customizable sound/reset/pause controls are implied. The test neither changed the clock nor wrote alarm slots. The original development implementation and automated acceptance remain described in [countdown.md](../countdown.md).
