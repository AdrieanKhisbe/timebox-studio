# CLI Bluetooth execution-permission comparison — 2026-10-19

Observed while validating [AdrieanKhisbe/timebox-studio#14](https://github.com/AdrieanKhisbe/timebox-studio/issues/14). The parent exclusively operated `main-evo` / `$MAC`, SDP RFCOMM channel 1. No implementation agent hardware access was involved.

## Controlled result

An initial apparent release-only failure was confounded by execution permissions. The parent ran this command from `/private/tmp/timebox-animation-and-text` using the exact same original binary and arguments:

```sh
.build/release/timeboxctl connect --device main-evo --channel 1 --json
```

| Execution context | Result |
| --- | --- |
| Tool's default sandbox (`use_default`) | RFCOMM open timeout after approximately 15 seconds; `-536870186`; no display payload sent |
| Standard tool approval (`require_escalated`) | Success on channel 1 in approximately 0.148 seconds; no display payload sent |

The parent also ran five connection-only variants with identical approved execution permissions:

| Binary | Seconds | Exit/status |
| --- | ---: | --- |
| Debug | 0.12 | 0 / ok |
| Untouched linker-signed release | 0.31 | 0 / ok |
| Release built with Swift `-Onone` | 0.14 | 0 / ok |
| Optimized release with generated debug entitlement | 0.30 | 0 / ok |
| Debug again | 0.12 | 0 / ok |

Finally the unchanged original release binary successfully uploaded `red-green-500ms.gif` with the same approved execution path: two effective frames, 1000ms, one packet, 94 wire bytes, no adaptation. See [input and playback evidence](evo-animation.md).

## What this establishes

The execution sandbox blocked the failing attempts. The comparison does not implicate release optimization, a missing callback selector, stale completion-flag polling, or a required new entitlement. Both builds contain the embedded purpose-string plist. Debug SwiftPM additionally ad-hoc signs its binary, whereas the original release retained linker-only signing; those differences were real but were not necessary causes of the observed failure. Ordinary re-signing alone did not resolve it, and the untouched release succeeded under approved execution.

No TCC reset, permission database edit, sandbox-profile bypass, transport modification or required signing script was introduced. The parent used the tool's ordinary approval mechanism. These findings concern this agent execution environment; they do not claim every user's terminal has the same restrictions. Compilation and mock sends alone cannot establish live Bluetooth access. If this environment reports a similar open timeout, use the standard approval path for the Bluetooth command before asking for further power cycles or inferring a protocol/build defect.

The underlying denied OS operation was not isolated, and no exact wall-clock timestamps or raw OS denial trace were retained. This controlled result does not establish that every Bluetooth timeout has the same cause. Timing values above measure command duration, not Bluetooth packet timing or display precision. Scratch binaries, signing variants and the local comparison harness remain outside the repository. No MAC address is published.
