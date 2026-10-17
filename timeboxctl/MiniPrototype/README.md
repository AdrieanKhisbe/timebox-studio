# THROWAWAY: original Timebox Mini experiment

Question: can an isolated 11x11 RGB444/escaped Mini encoder reuse the existing
macOS Classic transport for brightness, solid color, and a static image?

This is a native Bluetooth experiment, not a production model abstraction. Evo
encoding stays unchanged. It has no configuration persistence and never infers
which device is the Mini from its Bluetooth name. It does not implement Mini BLE,
alarms, live queries, or animation. Dry-run is the default.

```sh
swift build --product timeboxmini-prototype
.build/debug/timeboxmini-prototype demo
.build/debug/timeboxmini-prototype demo --send --name "YOUR MINI NAME"
.build/debug/timeboxmini-prototype image picture.png --send --name "YOUR MINI NAME"
```

Use full Xcode if required by your local Swift toolchain. Run the built executable
directly for Bluetooth/TCC rather than swift run. Channel defaults to 4 based on
the Mini reference; try --channel auto for existing SDP resolution, or set an
explicit channel. Each run prints its state and complete wire packet before sending.

The final pattern should show a white top-left pixel, red top edge, green left
edge, yellow diagonal, and blue bottom-right pixel (the odd 121st pixel).
Image input uses frame zero, nearest-neighbor stretching to 11x11, and black alpha
backing, then quantizes channels to their high four bits. No GIF playback is implied.

Protocol evidence:
- https://github.com/d03n3rfr1tz3/hass-divoom/blob/main/custom_components/divoom/devices/timeboxmini.py
- https://github.com/d03n3rfr1tz3/hass-divoom/blob/main/custom_components/divoom/devices/divoom.py
- https://www.divoom-gz.com/product/timebox-mini.html

Verdict: the existing Classic transport works with a separate Mini encoder.
On 2026-10-18, paired Mini `AKTBR` accepted the demo over RFCOMM channel 4; the
user confirmed the red display and orientation pattern appeared. A separate
image-file send also displayed the smiley, confirmed by the user. Brightness 30
was sent in the demo, but its independent visual effect was not checked.

Validation: the prototype builds and the existing 12 tests pass. Brightness 42
and color FF0080 at brightness 77 match independent hass-divoom golden packets.
A native 11x11 BMP produces the same packet as the generated orientation pattern.
The resized GIF displays correctly, but its pixels differ from the Pillow-based
reference fixture; exact cross-renderer resampling/color equivalence is unproven.

This settles basic static-display feasibility on this device, not full Mini
support. Production work needs explicit model selection, encoder integration,
protocol regression fixtures, and separate validation of other capabilities.
