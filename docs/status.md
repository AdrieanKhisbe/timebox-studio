# Live Evo status

```sh
timeboxctl status
timeboxctl status --device main-evo --json
timeboxctl status --address AA:BB:CC:DD:EE:01 --timeout 5 --yaml
```

Normal configuration, device selectors and channel override apply. This sends a
read-only `0x46` request on a fresh Classic link and returns values from a
checksum-validated device response. It never reports the last requested
brightness or mode as current state. Mock mode is unsupported.

Human output identifies the **configured channel** and both brightness fields. JSON/YAML (`--yml` alias)
return `command: status`, `status: ok`, `device` and:

| Data field | Meaning |
| --- | --- |
| `mode_raw` | Device-reported unsigned configured-channel byte |
| `mode` | Configured-channel name for values 0 through 5, otherwise null |
| `brightness` | System brightness, 0 through 100 |
| `light_brightness` | Separate night-light brightness, 0 through 100 |
| `raw_data` | All response data bytes, including unknown fields/extensions |

Names are clock (0), light (1), divoom (2), vj (3), music (4), and custom (5).
Mode 6 has conflicting source descriptions and is deliberately left unlabeled,
as are other unknown values; its raw number remains available. An unknown mode
is a successful live read, not an invalid invented mode.

The existing JSON/YAML names `mode` and `mode_raw` are retained for compatibility.
They describe the configured channel, **not necessarily the currently visible
content**. On the tested Evo, scrolling Hello animation remained visible while
`status` reported clock; explicitly selecting light then clock changed the byte
to 1 then 0 and the user confirmed dim blue then a white clock. A successful
status read cannot detect an overlay, identify the current design or prove what
pixels the display renders. Inactive channel-profile fields can remain in the
same response: the lighting RGB stayed blue while the white clock was visible.

An incomplete payload, invalid brightness, corrupt frame, rejected response,
disconnect or timeout fails with an error. No partial/cached success is returned.
Default timeout is five seconds after writing; it must be positive, finite and
at most 60 seconds. Transport connect/write timeouts are separate.

Inside the REPL, `status [--timeout SECONDS]` reads the current target. It closes
the persistent connection, performs the dedicated read and resumes the connection
only on success. On failure the selected target remains disconnected; use
`target NAME` to reconnect. REPL selectors/formats are rejected.

Swift apps use the shared typed query:

```swift
let status = try await TimeboxStatusReader.read(device: device)
// Or: TimeboxQueryReader.read(TimeboxQuery.status, device: device)
print(status.modeRaw, status.brightness, status.lightBrightness)
```

`TimeboxStatusDecoder` is protocol-only; `TimeboxStatusReader` delegates to the
[query ownership and correlation contract](device-queries.md). BLE/RCSP settings
receive decoding is not established. This operation does not enumerate alarms,
read stored content, return current image pixels, synchronize the clock or change
any settings. See the [field-map evidence and validation status](validation/evo-status.md).
