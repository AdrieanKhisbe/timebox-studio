# REPL editor implementation comparison

Both prototypes start at dev `86bee51` and adapt the actual timeboxctl REPL.
They are alternative branches, not changes merged into dev.

| Prototype | Branch | Worktree |
| --- | --- | --- |
| CommandLineKit | `prototype/repl-commandlinekit` | `/private/tmp/timebox-repl-commandlinekit` |
| Bestline | `prototype/repl-bestline` | `/private/tmp/timebox-repl-bestline` |

## Try the same simulated devices

From the main repository:

```sh
python3 private/scripts/repl/try-editor.py commandlinekit
python3 private/scripts/repl/try-editor.py bestline
```

Each launcher creates a scratch config with `desk` (Evo) and `mini` (Mini).
All device commands use `--mock`. No Bluetooth connection is opened. Try:

```text
brightness 20
color 0000FF
target mini
target
target desk
quit
```

Try Tab for command/device completion, Up for history, Ctrl-R, and Ctrl-D on an
empty prompt. Ctrl-C is intended to leave the session cleanly. By default history
is session-only. `--history-file /private/tmp/prototype-history` explicitly opts in
to a history file; use a different file for each editor when comparing them.

## Shared implementation contract

- `repl --editor plain` remains the default. Each branch adds only its own native
  editor name and an optional `--history-file` argument.
- Both retain existing command parsing, validation, target/model resolution and
  device transport behavior. Config-management prompts use their original input.
- Completion supplies the same commands, subcommands and configured device names;
  hints describe syntax and do not replace actual command validation.
- A terminal worker reads input while main services its run loop. Command and
  Bluetooth work stays on main, and cleanup waits for the input worker to finish.
- Pipes use plain input without ANSI line editing or history-file writes.
- Dependencies are pinned to the exact source revisions audited in the research.
  No upstream line-editor source was patched to conceal native limitations.

## Acceptance evidence

The shared harness is `private/scripts/repl/compare-editors.py`. It launches the
actual binaries with PTYs and the same scratch config, and retains JSON outcomes
plus raw terminal transcripts. The harness answers cursor-position queries with
a synthetic position, so its results establish byte/control flow rather than a
human-observed visual layout.

No real-device acceptance is claimed. A main-run-loop timer test demonstrates the
scheduling boundary while input blocks; it is not Bluetooth reconnection evidence.
The terminal restoration check excludes only macOS's transient PENDIN bookkeeping
bit and separately records exact termios differences.

### CommandLineKit

- Full repository suite: 192 tests passed; debug build passed.
- Actual dispatcher, arrow editing, command/target completion, unknown-target
  retention, Unicode logical name, history navigation/persistence, piped input
  and command execution following a resize passed the shared harness.
- Ctrl-C exits with code 0 and restores canonical/echo/signal settings.
- Native empty Ctrl-D rings a bell rather than exiting; Ctrl-R search is absent.
- Bracketed paste is not understood: the injected marker left a `~` prefix and
  caused a command error. A lack of successful early writes does not count as
  paste support or preserved input.
- Every native prompt waits for a terminal cursor-position response without a
  timeout. A terminal that does not answer can block before normal Ctrl-C input
  handling. The PTY harness supplies that response; this limitation is retained.

### Bestline

- Full repository suite: 191 tests passed; debug build passed.
- The same dispatch, editing, completion, target, Unicode logical-name, history
  save/reload, pipe and resize-followed-by-command checks passed.
- Ctrl-R found and executed an earlier command. Empty Ctrl-D exited cleanly.
- Native bracketed paste was announced, a multiline paste did not execute early,
  and a single-line pasted command executed correctly after Enter.
- Ctrl-C and pasted-input cancellation exited with status zero and restored
  terminal modes. Twenty fresh-process Ctrl-C attempts, alternating empty and
  partially typed input, all passed.
- An earlier adapter tried to capture Bestline's re-raised SIGINT; stress tests
  exposed delayed signal delivery beyond that scope. The final adapter instead
  uses Bestline's C input hook to return a read error for keyboard Ctrl-C before
  the library raises SIGINT. No upstream source changes or process-wide signal
  interception are needed. This is keyboard cancellation, not a general-purpose
  asynchronous command cancellation API.

## Verdict

Prefer Bestline for timeboxctl's interactive input. Both integrate with the actual
dispatcher, but Bestline supplies three useful behaviors that CommandLineKit's
reader lacks: searchable history, bracketed paste, and empty-prompt EOF. Its
adapter requires a small C input hook and exclusive ownership of global editor
state; CommandLineKit has per-reader state and a pure Swift adapter.

CommandLineKit's broader argument parser and output styling/layout helpers are
valuable for a new CLI. These prototypes retain timeboxctl's existing parser, so
those capabilities do not improve its REPL input. Adding them would be a separate
CLI redesign.

| Behavior tested | CommandLineKit | Bestline |
| --- | --- | --- |
| Editing, completion, history save/reload | Passed | Passed |
| Existing target/model dispatch, mock writes | Passed | Passed |
| Plain pipe fallback without ANSI/history writes | Passed | Passed |
| Ctrl-R search and execute | Absent | Passed |
| Bracketed single-line paste | Corrupts input | Passed |
| Empty Ctrl-D | Does not exit | Clean exit |
| Ctrl-C cleanup at ready prompt | Passed | Passed; 20 repeated attempts |
| Cursor-position response required | Unbounded prompt wait | Not required by tested prompt |
| Repository suite | 192 passed | 191 passed |

Neither branch is merged into dev. These are opt-in implementation experiments;
test-count differences reflect adapter-specific tests, not a quality score.

## Reproduce the comparison

Both branches include `scripts/prototypes/compare-editors.py` and
`scripts/prototypes/try-editor.py`. After building both worktrees, run:

```sh
python3 scripts/prototypes/compare-editors.py --interrupt-attempts 12
```

Use repeated `--binary EDITOR=/path/to/timeboxctl` arguments when the worktrees
live elsewhere. Results go to the current worktree's ignored `private/research/`
directory; raw transcripts and scratch config are retained under `/private/tmp`.
The harness reports unsupported capabilities as false rather than treating them
as a failed test suite. Inspect exit codes and `termios_restored`, including the
individual interrupt attempts, when assessing cleanup.

## Remaining production gates

Neither prototype adds modal Vi editing, arbitrary token syntax highlighting, or
an API to print background messages and restore the active prompt. Both still
need human visual checks for wide characters/emoji, wrapped input and terminal
resize behavior. Real-device idle-disconnection/reconnection acceptance remains
separate from this mocked comparison.
