# Bestline REPL comparison prototype

This branch adds an opt-in line editor to the existing `TimeboxCLIKit` REPL.
It pins `mattt/bestline-swift` at revision
`823c299247f2f35a4fd9a70f7bea4c8c9edcc946` through a real remote SwiftPM dependency.
The editor dependency is macOS-only; the package's existing iOS library deployment
target remains unchanged. Bestline itself requires Swift 6 tools.

After `swift build --product timeboxctl`, run without real Bluetooth writes:

```sh
.build/debug/timeboxctl repl --editor bestline --mock --model evo --address AA:BB:CC:DD:EE:01
```

For a real configured target, remove mock/address/model and use `--device main-evo`.
No real device test was performed for this prototype. Bluetooth responsiveness is
covered with a fake blocking reader and a main-run-loop timer, not a radio claim.

## Implemented scope

- Existing command parsing, device routing, model restrictions, and packet dispatch.
- Tab completion for commands, selected subcommands, and configured logical names.
- Usage hints for brightness, color, target, countdown, alarm, and display.
- Session history by default; explicit `--history-file PATH` loads/saves history.
- Native Bestline Ctrl-R search, bracketed paste, Unicode editing, and history keys.
- Ctrl-D on an empty input ends the REPL. Ctrl-C ends it with normal transport cleanup.
- A single editor worker blocks on terminal input while the main run loop services
  callbacks. Device command execution stays on the main thread.
- Bestline's process-global history/callbacks and terminal state are serialized;
  concurrent editor sessions are rejected. Callbacks contain only pure suggestions.

Default `repl` and `--editor plain` retain plain line input. If either stdin or stdout
is redirected, enhanced mode falls back to plain input without ANSI setup or history
file access. Unsupported terminal types also use plain input. Editor/history flags
outside REPL fail before discovery/connection; they are also rejected inside commands.
Configuration-selection prompts retain their independent injected input boundary.

## Interrupt adapter

Bestline normally restores raw mode and bracketed paste, then re-raises SIGINT.
Capturing that process signal raced with deferred delivery during initial testing,
so this adapter avoids signal manipulation entirely. Its supported C custom-read
hook recognizes the Ctrl-C input byte and returns `-1`/`ECANCELED`. Upstream discards
the partial line, restores the terminal, and returns nil. Returning zero would
submit a partial buffer, so the hook deliberately returns a negative error.
The hook is active only during serialized line input and resets to upstream defaults
afterward. Native history search, completion, and paste still use upstream code.
Ctrl-C during command execution and externally delivered SIGINT retain the existing
process behavior; this does not provide general command cancellation.

## Comparison limitations

Bestline brings history search and bracketed paste absent from CommandLineKit's
reader. It does not provide a public background-message/prompt redraw API, general
syntax highlighting, or demonstrated modal Vi editing. Its Swift read API returns
`nil` for both EOF and read errors. History capacity is compiled into the upstream
C implementation (1,024 entries), and callbacks/history are global rather than
reader-instance state. ANSI output from unrelated callbacks can disturb the prompt.
Completion intentionally matches the other prototype; it is not a shell parser or
file-path completion service. Saved history can contain command arguments and is
only enabled by an explicit path. History save errors are reported at shutdown.

## Verification

The focused XCTest additions exercise existing command dispatch through injected
REPL input, exclusive prompt ownership, early option rejection, configured-name
completion, run-loop responsiveness, and nonterminal history/ANSI fallback. Existing
executable integration tests also invoke the enhanced flag through pipes.

The parent comparison harness exercises both prototypes with the same scratch config
and mock transport. Its recorded Bestline observations include arrow editing,
completion, Unicode logical names, history navigation and reload, Ctrl-R recall,
native bracketed paste without premature command execution, Ctrl-D, resize followed
by command dispatch, and terminal-mode restoration. An intermittent worker SIGINT
delivery race was found during repeated Ctrl-C sessions and addressed by the custom
read-hook adapter above. After rebuilding, all 20 fresh-process interrupt attempts
exited normally with terminal modes restored. The complete suite passed 191 tests.
The shared comparison report records the detailed PTY observations and the macOS
PENDIN bookkeeping bit separately from canonical/echo/signal-mode restoration.

No commits, pushes, real-device writes, or user history/configuration writes are made
by this prototype's validation.
