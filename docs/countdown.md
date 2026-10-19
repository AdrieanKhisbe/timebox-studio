# Device countdown

Use `timeboxctl countdown start 05:00` and `timeboxctl countdown stop`, also available in the REPL. Normal selectors and JSON/YAML apply to ordinary CLI commands. `TimeboxCountdownDuration` accepts strict ASCII MM:SS from 00:01 through 59:59; `TimeboxClient.startCountdown(_:)` and `stopCountdown()` send device commands. No host sleeping timer or delayed notification is involved.

## Evidence and discrepancy

The [manufacturer Bluetooth tools page](https://docin.divoom-gz.com/web/#/5/265) specifies opcode 72, tool index 3 and minute/second bytes, with seconds maximum 59. Its countdown control prose says 0=start and 1=cancel. **That control mapping conflicts with the official app's actual Bluetooth path.**

Divoom Android 3.8.40 (APK SHA256 `d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`, provenance in [alarm investigation](validation/evo-finite-weekday-follow-up.md)) has the following trace, inspected using JADX 1.5.6:

- `CountDownFragment.mOnclick`: selecting a duration or pressing start sets its running boolean true; pressing stop sets false.
- `ToolServer.k(boolean, int, int)`: Bluetooth branch passes that boolean and the minute/second values unchanged to `CmdManager.s3`.
- `CmdManager.s3`: emits `72 03 (running ? 01 : 00) minutes seconds`.
- `DateTimePicker` constructor limits both minute and second pickers to 0...59. `CountDownFragment` rejects zero in both fields.
- [hass-divoom's own show_countdown encoder](https://github.com/d03n3rfr1tz3/hass-divoom/blob/main/custom_components/divoom/devices/divoom.py#L755-L768) independently uses the same control mapping.

Implementation follows the official app, recording rather than hiding this documentation conflict. Stop sends `72 03 00 00 00` (the reference's zero fields). The supported range is the app's envelope, not a proven absolute Evo firmware maximum. Zero rejection matches the app and the issue's proposed policy; hours and values beyond the picker are rejected without truncation. No undocumented pause/resume/reset or sound controls are exposed.

## Hardware acceptance

On 2026-10-19, the parent-owned hardware session validated `main-evo` on RFCOMM channel 1: a 00:05 countdown visibly reached zero and produced completion sound; a fresh 02:00 countdown visibly ticked, then `countdown stop` stopped it with an animation. This corroborates the app-derived control mapping over the conflicting manufacturer prose. See the [observation report](validation/evo-countdown.md).

The earlier 00:30 start/stop attempt was ambiguous and is not counted as stop acceptance. The commands were standalone CLI sends, disconnecting after transmission; the later stop command therefore used a fresh connection. Restart, display-channel changes, long-term persistence, exact elapsed-time accuracy and the maximum duration remain untested. Sound selection and stop-animation customization are not exposed. Structured output continues to report `sent`; physical observations do not establish a response/readback protocol.
