# Verified device queries

[AdrieanKhisbe/timebox-studio#11](https://github.com/AdrieanKhisbe/timebox-studio/issues/11)
provides a reusable typed query engine without depending on alarm types.

A query supplies a sourced request payload, expected response opcode and typed
payload decoder. `TimeboxQueryReader.read(_:device:channel:timeout:)` opens and
closes a dedicated Classic RFCOMM connection on the main actor. Application-level
status and alarm adapters are added by their respective feature stages.

`TimeboxQuery<Response>` belongs to TimeboxKit: a request payload, expected reply
command and throwing typed data decoder. Its initializer frames the request.
`TimeboxResponseDecoder` validates Evo NewMode delimiters, little-endian length,
additive checksum and the `04 command 55` success envelope before exposing data.
No CLI formatting or transport dependencies enter this layer. Settings fields are not inferred from outgoing writes.

`TimeboxQueryReader` and `TimeboxQueryTransport` belong to TimeboxBluetooth. The
transport exposes raw `onData` events, synchronous query writes and run-loop
pumping. All operations and events must run on the main thread. A caller may
supply an exclusively owned, already connected fresh transport using
`read(_:from:timeout:isCancelled:)`. Existing receive handlers are rejected
without replacement. Timeout is finite, greater than zero and at most 60 seconds;
connection and write retain their separate bounded transport timeouts.

## Ownership, correlation and failure

Evo replies have no transaction identifier. Sequential requests on a persistent
link would allow a late reply to satisfy the next identical request. Therefore
every read owns one request on a **fresh physical connection**, and disconnects
on success, timeout, cancellation, write failure, decoding failure or link loss.
There is no retry or second request on that link. The Classic implementation
rejects a query after prior traffic, during another write, or during a query.
It permits exactly one query write, rejects normal synchronous/async writes and
reconnects until the query owner releases the link. A second concurrent caller
receives `TimeboxQueryError.busy`; it is not queued. An external disconnect does
not release ownership before the reader finishes cleanup.

RFCOMM callbacks are scoped to the bridge that belongs to the current physical
link. Obsolete bridges cannot deliver bytes or close events into its replacement.
Fresh-link separation excludes replies from an earlier transaction; the expected
command plus sourced command semantics establish association on the new link.
It does **not** establish safe correlation for arbitrary opcodes that might also
be unsolicited notifications. Add such queries only after evidence distinguishes
the requested reply from that notification. An unrelated command never completes
a query. Strict framing rejects malformed envelopes, including rejected commands;
there is no speculative resynchronization or partial-success fallback.

Fragmented/coalesced valid frames are assembled independently of transport
callbacks. The first matching, typed valid response completes the query; duplicate
matching replies cannot initiate another transaction. Missing data is timeout;
pending partial bytes at deadline are `invalidResponse`. Typed schema failures
also become `invalidResponse`; no incomplete array is returned as a full result.
Transport write failures retain their underlying typed error. Cancellation is
checked before writing and during/after waiting. Error paths close the owned
transport; an invalid argument or busy owner leaves someone else's transport intact.

The query engine owns `onData` only for its lifetime. Custom transport conformers
must enforce the documented beginQuery/endQuery ownership rules and exclude
callbacks from previous physical connections. They must not reconnect underneath
an active reader. The Classic implementation enforces this contract; arbitrary
third-party conformers cannot be assumed to do so.

## Evidence and scope

The framing contract derives from the previously captured Evo alarm reply,
archived with [AdrieanKhisbe/timebox-studio#12](https://github.com/AdrieanKhisbe/timebox-studio/issues/12).
The generic engine tests use an explicitly synthetic opcode and independently
specified checksum fixtures. They cover fragmented/coalesced frames, corruption,
typed-schema failure, timeout, cancellation, write failures, nested access,
prior traffic and obsolete callbacks. They establish engine behavior, not a new
device command or fresh hardware acceptance.

BLE/RCSP writes remain supported and unchanged. The observed RCSP write ACK is
not evidence for an application settings/alarm reply decoder: no RCSP query
support is claimed. Mini OldMode framing is likewise outside this Evo decoder.
There is no general settings model until its field map has been established;
[AdrieanKhisbe/timebox-studio#13](https://github.com/AdrieanKhisbe/timebox-studio/issues/13)
tracks that work. Multiplexing, automatic retries and receive-history emulation
are not provided.
