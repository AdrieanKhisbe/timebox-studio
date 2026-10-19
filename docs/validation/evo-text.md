# Evo scrolling text hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#18](https://github.com/AdrieanKhisbe/timebox-studio/issues/18).

The parent exclusively operated logical target `main-evo`, Bluetooth address `$MAC`, SDP-resolved RFCOMM channel 1. Command input: `.build/debug/timeboxctl text "Hello" --device main-evo --json` on the media feature branch.

The CLI resolved `Menlo-Regular` at 12px and produced 54 source/effective frames, 5400ms total, 13 packets and 2542 wire bytes, with no lossy adaptation. The user confirmed the text scrolled leftward, was upright and readable, and repeated. This is physical evidence of readable basic Latin rasterization and a successful ordered multi-packet animation upload in that debug session.

The observation does not measure precise timing/spacing, validate every glyph/font/Unicode/limit case, or claim cross-platform identical rasterization. Unsupported-glyph rejection, quoting and bounds remain covered by automated fixtures. No raw notification trace, exact attempt timestamps or power-cycle persistence observation was retained.

The [animation hardware report](evo-animation.md) records repeated optimized-release RFCOMM-open timeouts before any transmission, including an unsuccessful ordinary ad-hoc re-sign experiment. This text observation uses the debug binary and does not establish release hardware acceptance. No new device access was performed by the implementation agent.
