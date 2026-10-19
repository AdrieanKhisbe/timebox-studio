# Device stopwatch

`timeboxctl stopwatch start`, `stopwatch stop`, and `stopwatch reset` send device stopwatch operations. These commands also work in the REPL on its current target. Ordinary commands support the shared selectors and structured JSON/YAML output. Apps use `TimeboxClient.stopwatch(_:)` with typed `TimeboxStopwatchAction`.

The [manufacturer Bluetooth tools page](https://docin.divoom-gz.com/web/#/5/265) specifies mode 0 with control flags 0=pause, 1=start, 2=reset. The original Divoom Android 3.8.40 `StopwatchFragment.mOnclick` sends start=1 and stop=0; its reset confirmation sends 2. All three pass through `ToolServer.j` to `CmdManager.t3`, emitting `72 00 flag`. The APK SHA256 is `d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`; see [provenance](validation/evo-finite-weekday-follow-up.md). [hass-divoom's show_timer](https://github.com/d03n3rfr1tz3/hass-divoom/blob/main/custom_components/divoom/devices/divoom.py#L985-L992) independently emits mode 0 and the supplied control, defaulting to reset. No decompiled code is distributed.

Reset therefore has a distinct verified encoding, rather than being a no-op or a guessed stop/start sequence. Stop is documented as pause; the app's toggle implies subsequent start resumes. The 2026-10-19 parent-owned `main-evo` test confirmed progression after reset/start, pause with elapsed retained, resume from that paused value, and reset while running clearing/stopping at zero. The host sends each requested operation unchanged and does not infer or cache device state. No live elapsed-time read is exposed. Structured `sent` means transmission, not confirmation that the visible counter progressed or cleared.

See the [hardware observation report](validation/evo-stopwatch.md). Every operation was a separate one-shot connection, supporting these immediate disconnect/reconnect transitions. Repeated start while active, repeated stop, reset while paused, power-cycle and display-channel persistence remain untested. No elapsed readback or precision measurement was performed. The final observed state was stopped at zero.

## Original Mini

The same commands and library API select Mini `45 06 ACTION` with OldMode escaping
when the resolved model is Mini. Start/pause/resume/reset were visibly confirmed
on AKTBR. See [Mini validation](validation/mini-clock-stopwatch-alarms.md). No native
Mini countdown or elapsed-time readback is implied.
