# Evo stopwatch hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#17](https://github.com/AdrieanKhisbe/timebox-studio/issues/17).

The parent agent exclusively controlled this hardware session; this report records its supplied observations. Logical target: `main-evo`, Bluetooth address `$MAC`, SDP-resolved RFCOMM channel 1. Each action was a standalone CLI command, reporting 9 bytes sent, with a separate connection and normal post-write hold/disconnect. No exact wall-clock timestamps, raw packet trace, elapsed readback or precision measurement were recorded.

| Sequence | Human observation | Acceptance |
| --- | --- | --- |
| `stopwatch reset`, then `stopwatch start` | User confirmed elapsed time increasing | Reset/start progresses visibly |
| `stopwatch stop` | User confirmed paused display retaining elapsed time | Stop pauses rather than clears |
| `stopwatch start` again | User confirmed resumption from the paused value | Start resumes rather than restarts in this transition |
| `stopwatch reset` while running | User reported “stopped at 0” | Reset clears and stops |

The distinct start/stop/reset encodings were established by sourced packet fixtures. The hardware session retained write byte counts rather than a new raw capture. The observed final state was stopped at zero.

The sequence demonstrates these immediate transitions across the one-shot commands' normal disconnects. It does not establish persistence across power cycles, arbitrary reconnect delays or channel changes. Repeated start while already running, repeated stop, reset while paused, power-cycle and display-channel behavior remain untested. No live counter-read API or timing accuracy is claimed. See [stopwatch.md](../stopwatch.md) for the interface and protocol provenance.
