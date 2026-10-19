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

## Pending hardware acceptance

No Bluetooth connection or hardware write was made for this implementation. Verify 00:05 ticks and completes, a longer countdown stops, restart behavior, disconnect behavior, and switching display channels. Record completion sound/display behavior without assuming an alarm sound can be selected. Until then structured output reports `sent`, never visible ticking or completion verified.
