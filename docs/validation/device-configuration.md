# Device/configuration validation — 2026-10-18

Scope: T2–T6, AdrieanKhisbe/timebox-studio#3 through
AdrieanKhisbe/timebox-studio#7. This records automated coverage and transport
observations; it does not replace visual acceptance testing.

Environment: macOS 15.8 (arm64), Xcode 26.2, Apple Swift 6.2.3.

- `swift test`: 39 tests passed, including the existing protocol fixtures.
- `swift build --configuration release --product timeboxctl`: passed.
- Resolver tests cover selector precedence, audio endpoints, ambiguous discovery,
  offline defaults and no fallback after selection.
- Filesystem tests cover first saves, repeated saves, name collisions, canonical
  MAC identity, offline retention, malformed/duplicate config rejection, write
  failure, Unicode comments, CRLF, flow mappings and unknown fields.
- CLI-boundary tests use controlled discovery/transport with real config files,
  stdout/stderr capture and REPL input. They cover interactive default selection,
  rename/cancellation, raw config output, target switching/failure, format parity,
  simulation, invalid input, failed writes and terminal styling.
- Executable tests launch `.build/debug/timeboxctl` with temporary config files
  and mock transport to verify the actual dispatcher, config lifecycle, REPL,
  JSON stdout and nonzero machine-readable failures.

A real paired Evo accepted this command using its auto-resolved RFCOMM channel 1:

```sh
.build/debug/timeboxctl brightness 50 --address "$MAC" --json \
  --config /private/tmp/timebox-acceptance-config.yml
```

Exit 0, eight bytes transmitted, stdout result `status: sent`, command
`brightness`, data `brightness: 50`, `bytes: 8`. The MAC is intentionally redacted.
Connection/write diagnostics were emitted via stderr. No visual confirmation was
requested for this individual transmission.

Remaining manual acceptance: walk through prompts in a human terminal; verify
display changes while switching between two physical Evo devices. Automated
routing tests already verify unknown/failed switches cannot write to an old
target, but they cannot establish a device's visible response.
