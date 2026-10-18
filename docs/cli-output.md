# CLI output

`list`, `brightness`, `color`, `image`, `connect`, `send-hex` and `alarm list` accept `--json`
or `--yaml` (`--yml` alias). Conflicting formats fail. Both encode the same
one-result model; stdout contains that result only. Diagnostics, errors and
`list --save` hints go to stderr. Human output remains the default; list names
are emphasized only on a terminal, unless `NO_COLOR` is set.

```json
{"command":"brightness","device":{"name":"desk","mac":"AA:BB:CC:DD:EE:01"},"status":"sent","data":{"brightness":50,"bytes":8}}
```

`command`, `status` and `data` are always present. `device` is included when a
single target was resolved; its logical `name` is null for unconfigured addresses.
Its MAC is the selected Bluetooth address. Device selection and transmission use
the same path regardless of output format.

| Command | Data on success |
| --- | --- |
| list | `devices` array, empty when nothing matches |
| brightness | `brightness` percentage, `bytes` written |
| color | `color` uppercase RRGGBB, `brightness` percentage, `bytes` written |
| image | `path`, encoded `width`/`height` (16), `bytes` written |
| send-hex | `bytes` written |
| connect | selected RFCOMM `channel` (null if unavailable); connection is closed on exit |
| alarm list | live `alarms` array of ten slot records; see [alarm schema](alarms.md) |

Each list entry has `name` (logical or null), `mac`, `bluetooth_name`, `paired`,
`connected`, `source` (`bluetooth` or `mock`), and `is_timebox`. The connected flag
is discovery metadata, not a claim that LED control is reachable. `--all` includes
other paired Bluetooth devices. Listing never connects or infers an online state.

Writes report `sent` after transport success, never visual confirmation.
`--mock` reports `simulated`; discovery and real connection success report `ok`.
Simulation does not claim hardware transmission or readback. Image dimensions
describe encoded data, not a device query.

Failures report `status: error` and `data: {code, message}`. Exit codes are 0 for
success/simulation, 2 for invalid arguments, and 1 for config, execution or
transport failures. Error codes currently used by this CLI are `invalid_arguments`,
`invalid_config`, `device_not_found`, `ambiguous_device`, `connection_failed`,
`write_failed`, `query_timeout`, `invalid_media`, `unsupported` and
`invalid_response`, `cancelled`, `query_busy`, and `execution_failed` (unexpected execution errors).
Alarm query cancellation and an already occupied receive handler are explicit
errors, not empty lists. With conflicting format flags,
the first requested format carries the error. Diagnostics also go to stderr.

`config show` is an exception: YAML emits the original file bytes including
comments; JSON emits the loaded plain config object. It has no command envelope.
Config editing commands do not accept these flags. Config-show/edit errors are
reported on stderr with a nonzero exit, without a fabricated config object.

The REPL remains interactive (`target`, `help`, `quit`); formats are rejected.
Low-level scan/inspect/probe/listen/BLE diagnostics do not yet have streaming
schemas. Format requests for those commands fail explicitly before Bluetooth
access. Keep their default human output for diagnostic use.
