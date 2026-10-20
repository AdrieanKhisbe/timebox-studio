# CommandLineKit REPL comparison

This isolated prototype uses the existing `TimeboxCLIKit` dispatcher, target switching,
model resolution and Classic Bluetooth transport. It adds a terminal input adapter;
it does not replace command parsing with CommandLineKit's argument parser.

## Try it

After `swift build`, run from this worktree in a normal terminal:

```sh
.build/debug/timeboxctl repl --editor commandlinekit --mock --address AA:BB:CC:DD:EE:01 --model evo
```

`--mock` prevents hardware connections. To try the connected device deliberately,
replace the mock/address/model options with `--device main-evo --config PATH`.
The default editor remains `plain`; `--editor plain` explicitly selects existing behavior.
Both stdin and stdout must be terminals for the enhanced editor. Piped input or redirected
output uses plain input with a diagnostic, no ANSI editor and no history-file access.

Session history is limited to 1,024 commands, skipping blanks and adjacent duplicates.
Persistence requires an explicit path:

```sh
.build/debug/timeboxctl repl --editor commandlinekit --history-file /tmp/timebox-commandlinekit-history --mock --address AA:BB:CC:DD:EE:01 --model evo
```

That path is loaded if it exists and saved on session cleanup. No default user file is
created. Its parent directory must exist; save failures are reported to stderr.
Editor/history options are rejected on non-REPL invocations before configuration,
discovery or transport work. They are also rejected inside REPL commands.

## Implemented surface

- Native line editing and history navigation, including arrows, Home/End,
  Ctrl-A/E/B/P/N/U/K/W/T/L and Alt-B/F as provided upstream.
- Tab completion for root commands; display/time/stopwatch/countdown/alarm subcommands;
  `target current` and configured logical device names. Tab cycles complete-line candidates.
- Dim usage hints for brightness, color, target, countdown, alarm and display. These
  describe syntax; native command validation remains authoritative.
- Ctrl-C exits cleanly through the library's throwing cancellation path and transport cleanup.
- One terminal input worker per outstanding read. The main thread pumps its run loop while
  waiting, allowing main-thread Bluetooth callbacks. A read completes before dispatch,
  another read, history saving or transport teardown. Configuration prompts retain their
  separate injected `readLine` boundary.

There is no background-message redraw facility; callbacks must not print over the active
editor. This prototype does not add raw-mode keyboard shortcuts to the command dispatcher.

## Native limitations retained for comparison

- Empty-prompt Ctrl-D rings a bell; it does not exit. Use `quit`, `exit` or Ctrl-C.
- No Ctrl-R search, modal Vi editing or bracketed-paste interpretation.
- No general syntax highlighting, asynchronous input cancellation, terminal-resize hook,
  or prompt restoration around background output is added.
- Each prompt sends a cursor-position query (`ESC[6n`) and waits without a timeout for
  an `R`-terminated response. A terminal that does not answer can hang and consume typed
  characters; a PTY harness must emulate `ESC[1;1R`. Ctrl-C before that reply is not handled
  by the normal cancellation branch. This is an upstream adoption blocker for terminals
  without this response, not solved by the run-loop pump.
- Unicode accepts text, but terminal-column width is still the upstream editor's concern.
  Wide characters, combining sequences and emoji require interactive comparison.
- Unsupported terminal types (`TERM=dumb`, empty TERM, Xcode, etc.) report an error with
  a suggestion to use `--editor plain`, before connecting.
- Terminal disconnect handling has an adapter HUP guard when upstream returns an empty
  line; it is not a replacement for upstream cancellation support.

The pinned dependency is
[`objecthub/swift-commandlinekit@b3c68f8`](https://github.com/objecthub/swift-commandlinekit/tree/b3c68f89f7096c57f26417915595122f099f1622).
Its source is unchanged. It is a dependency of `TimeboxCLIKit`, not of the public
`TimeboxKit` or `TimeboxBluetooth` library products.

## Validation

`swift test`: **192 tests passed**, zero failures. `swift build`: passed.
Debug binary: `/private/tmp/timebox-repl-commandlinekit/.build/debug/timeboxctl`.

Automated suite covers invalid flag scope before I/O, actual dispatcher packet output
through injected enhanced input, unchanged plain/piped paths, exclusive prompt ownership,
cleanup, completion grammar and configured names, and a main-run-loop timer firing while
the input worker is blocked. The shipped executable is exercised with pipes, a scratch
config and mock transport; no ANSI bytes or history writes are permitted on that path.

No real-device commands were used for this comparison. The run-loop test checks the
callback scheduling boundary with a timer; it does not claim physical Bluetooth validation.
The parent comparison harness separately records PTY keyboard behavior and terminal
restoration for both candidates.

The shared PTY comparison confirmed command dispatch, Tab completion, configured-target
selection, history recall and persistence, Unicode logical-name dispatch, piped fallback,
and command execution after terminal resize. Ctrl-C exited with status zero. Empty-prompt
Ctrl-D rang without exiting; Ctrl-R search was absent. Bracketed paste corrupted the
command with a `~` prefix, as expected from the missing paste-delimiter handling.
These checks do not establish correct visual column placement for every Unicode sequence
or responsive redraw on resize.

After short sessions, echo, canonical input and signal flags were restored. The exact
termios comparison differed only in the kernel-maintained `PENDIN` bit (`0x20000000`),
which the harness records separately rather than interpreting as a raw-mode leak.
The harness answered cursor-position queries; the unbounded-wait caveat above remains.
