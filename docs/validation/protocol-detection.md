# Protocol selection and read-only detection

Tracks AdrieanKhisbe/timebox-studio#20. The CLI can use `legacy11` (original
Timebox/Mini) or `evo16` without asserting an exact product identity. Protocol-only
targets report `model: null` with independent `protocol_family`/`protocol_source`
fields. Existing product model overrides remain compatible.

## Configuration and precedence

The optional per-device YAML `protocol` field accepts `legacy11` or `evo16`.
Omit it for automatic resolution. `model` and `protocol`, when both saved, must
agree. Unknown values fail config validation. Save, select and rename operations
preserve protocol fields, comments and unknown fields.

CLI resolution uses explicit `--protocol`, then explicit `--model`'s protocol,
then saved protocol, then a known model's protocol. `--protocol auto` bypasses
these protocol shortcuts and performs a live read. `--model auto` ignores the
saved product model, independently of any protocol override. A retained known
model must agree with the selected/detected protocol; mismatches reject before
control writes. To disregard stale identity, use `--model auto` as well.

The selected target and channel are fixed before detection. Startup overrides
apply only to the initial REPL target. Target switching resolves its own config
and protocol; a failed resolution preserves the previous target. `connect` and
`send-hex` do not detect protocols; `list --save` performs no protocol reads.

## Settings probe and latency

The probe sends only settings opcode `46`. It starts with the canonical raw
request `01 03 00 46 49 00 02`. If no settings reply arrives within350ms (or half
the query timeout when shorter), it closes that link and tries the escaped
request `01 03 06 00 46 49 00 02` on a fresh link. Connection failures, corrupt
settings frames, unfamiliar layouts and cancellation do not trigger this retry.
The request budget defaults to5s; native RFCOMM connection establishment has its
own timeout and is not included in that budget. Each connection settles150ms.

Replies require a complete checksummed `04 46 55` envelope and a recognized
settings layout:20 bytes with raw framing for Evo,23 with valid escaped framing
for legacy11, plus valid brightness fields. Frames without reserved interior
bytes can be valid in both dialects; the recognized layout then selects the
family. This is compatibility detection against observed firmware layouts,
not a retail product identifier or a guarantee for every future firmware.
Extended/unrecognized layouts fail closed and request an explicit override.

Fragmented replies, greetings and unrelated notifications are handled without
treating them as identity. A read owns its callback/query reservation, has a
bounded buffer, and disconnects/cleans up on completion or failure. No control
operation is used as a probe.

The automatic path adds connection/settling/query overhead to commands that
otherwise only write. One-shot `status` directly uses its detection snapshot,
avoiding another query. A REPL resolves the family once per target and always
reads fresh status afterward. Explicit/saved protocol or model skips detection.
Structured results expose `protocol_query_ms` and `protocol_detection_ms`; the
latter includes connection and settling time. No live timing result is claimed:
the first original-device timing attempt timed out opening RFCOMM before the
settings request could be sent.

## Automated coverage

`ProtocolDetectionTests` exercises both dialects across every frame boundary,
reserved bytes, the original-device capture, greetings/unrelated messages,
the timeout-only escaped fallback, checksum/layout/brightness failures,
conflicting snapshots, query cleanup/cancellation, protocol-only CLI/config
selection, truthful model metadata, immediate status reuse, fresh REPL reads
and independent target switching. These use simulated transports rather than
claiming fresh hardware acceptance.

The CLI uses the existing model-parameterized codecs internally as protocol
adapters; that surrogate is never reported as a detected Mini/Evo identity.
The public read-only `TimeboxProtocolDetector` is also available to library
callers. `TimeboxClient(model: nil)` retains its conservative product-identity
resolution; this change does not silently alter that API or enable legacy BLE.
