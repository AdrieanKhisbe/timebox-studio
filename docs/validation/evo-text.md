# Evo scrolling text hardware observation — 2026-10-19

Issue: [AdrieanKhisbe/timebox-studio#18](https://github.com/AdrieanKhisbe/timebox-studio/issues/18).

The parent exclusively operated logical target `main-evo`, Bluetooth address `$MAC`, SDP-resolved RFCOMM channel 1. Command input: `.build/debug/timeboxctl text "Hello" --device main-evo --json` on the media feature branch.

The CLI resolved `Menlo-Regular` at 12px and produced 54 source/effective frames, 5400ms total, 13 packets and 2542 wire bytes, with no lossy adaptation. The user confirmed the text scrolled leftward, was upright and readable, and repeated. This is physical evidence of readable basic Latin rasterization and a successful ordered multi-packet animation upload in that debug session.

The observation does not measure precise timing/spacing, validate every glyph/font/Unicode/limit case, or claim cross-platform identical rasterization. Unsupported-glyph rejection, quoting and bounds remain covered by automated fixtures. No raw notification trace, exact attempt timestamps or power-cycle persistence observation was retained.

The earlier apparent release-build connection defect was resolved by a [controlled execution-permission comparison](cli-bluetooth-execution.md): the identical original release command timed out under default sandbox execution, then connected through the ordinary approved execution path. The unchanged release also uploaded the deterministic red/green animation successfully. No source, optimization, signing or entitlement change was needed. The parent subsequently ran the unchanged original release CLI for `text "Hello"` through that approved execution path. It successfully transmitted 13 packets / 2542 wire bytes; the local mock resolved the same Menlo font. This adds live release text-upload evidence. The earlier human visual acceptance remains from debug; no new release-specific visual confirmation is claimed. No new device access was performed by the implementation agent.
