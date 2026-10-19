# Scrolling text

`timeboxctl text "Hello"` and REPL `text "Hello"` render text into the same [animation pipeline](animation.md), with no device-native text opcode. Apps use `TimeboxTextRenderer.render(_:)` and `TimeboxClient.send(text:)`. The result travels as the verified legacy animation frame/chunk format. The complete animation is validated before connecting or sending.

Defaults: the platform's system fixed-pitch font (`CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil)`), white on black, 12 pixels at the 1:1 bitmap scale, centered vertically, moving left one pixel every 100ms. A blank viewport precedes entry and follows exit. The resolved PostScript font name is printed on stderr and in structured CLI results; on the development Mac it resolves to `Menlo-Regular`. CoreText shaping and platform font versions can change rasterization, so cross-platform identical pixels are not promised. No font files are bundled.

The selected font must directly support every supplied Unicode scalar; unsupported characters are listed with their Unicode code points instead of silently accepting fallback glyphs. Controls/newlines and empty/whitespace-only messages fail. Unicode supported by the resolved font is accepted; emoji and supplementary-plane characters are not automatically substituted. Quoted CLI messages preserve literal internal quotes; the REPL accepts an outer single/double quote pair and escaped double quotes/backslashes. Its unquoted message retains internal quotes.

There are no text formatting or adaptation flags. Text is never silently truncated, palette-reduced or temporally thinned. Inputs above the host 1024-UTF16-unit guard, the selected model's glyph-height/raster/frame envelope, or the applicable upload envelope fail before a write. Long text must be shortened; adding text adaptation requires a separate contract. Rendered text reuses all animation transmission behavior, including stopping on partial failure without retry.

## Explicit host streaming

`timeboxctl text "Hello Mini" --stream --device mini` keeps the Mac connected for
one complete scroll, then disconnects. In the REPL use `text --stream "Hello Mini"`;
the flag must precede the message and the existing selected target stays connected.
This mode is also available on Evo. Ordinary Evo `text` retains native looping
animation upload. Mini text requires explicit `--stream` because a complete scroll
cannot fit the conservative native 12-frame buffer without dropping content.

Streaming uses static-image packets at a target 100ms per one-pixel step, including
blank entry and exit. Mini uses a system fixed-pitch 9px font in its 11×11 viewport;
Evo keeps 12px/16×16. All glyphs and packets are validated before connecting. The
host paces frames with a monotonic clock, accounts for write time, and stretches
playback on slow writes rather than skipping frames or producing catch-up bursts.
It does not use the native animation delay field or its minimum playback interval.

The process must keep running for the complete scroll. Ctrl-C terminates the CLI;
there is no autonomous repeat, offline playback or automatic resume. Errors stop
at the first failed write without reconnecting or replaying. JSON/YAML success is
emitted only after the final frame's hold and reports `playback: host_stream`,
`completed: true`, `repeats: false`, frame count and target duration. Completion
describes host transmission, not pixel readback or measured cadence.

Library callers prepare `TimeboxTextStream(message, model: .mini)` or use
`TimeboxClient(model: .mini).stream(text:)` on an existing connection. Cancelling
the task stops further writes; the caller still owns and closes that connection.
`send(text:)` retains its native-animation behavior and Mini guard. See the
[Mini streaming report](validation/mini-streaming-text.md) for source and hardware evidence.

Tests cover a repeatable upright F raster and one-pixel frame shifts, white/black pixels, direct supported Unicode, missing glyphs, quotes, empty/oversized input, structured output, REPL targeting and exact animation packet parity. Raster tests describe invariants rather than claiming system font bitmaps are immutable across OS releases. The parent-owned 2026-10-19 `main-evo` test confirmed `Hello` visibly scrolled leftward, upright, readable and repeating with the **debug** CLI. Metadata: `Menlo-Regular` at 12px, 54 frames, 5400ms, 13 packets, 2542 wire bytes, no adaptation. See [hardware observations](validation/evo-text.md). Exact cadence and spacing were not measured, and other Unicode/font/limit variants remain untested on hardware. The initial release connection failures were resolved to the execution sandbox: the unchanged release connected and sent the red/green animation using standard approved execution. No code/signing fix was required. The parent also successfully uploaded Hello with the unchanged release CLI using approved execution (13 packets, 2542 bytes). Human confirmation of upright readable playback was obtained in the earlier debug session; no additional release visual observation is claimed.
