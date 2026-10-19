# Original Mini: remaining countdown and model identity evidence

Follow-up for [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20),
2026-10-19. Source-only: no speculative commands, firmware operations or radio
probes were performed. These findings narrow the evidence gaps; they do not
prove that every Mini firmware lacks the capabilities.

## Native countdown

The official Android app 3.8.40 selects `MiniDiscover`, `MiniUiArch` and `OldMode`
for original `TIMEBOX_MIN`. `DiscoverModel.s` includes stopwatch and scoreboard
but omits countdown. Both the initial home list and the add-tools palette derive
from that catalogue. Separate MiniToo and Evo catalogues do include countdown.
The shared CountDownFragment routes through ToolServer to `CmdManager.s3`, which
builds `72 03 ENABLE MINUTES SECONDS`; this generic builder does not establish a
Mini-specific duration path. The shared stopwatch route also uses modern `72`,
whereas the Mini's physically verified legacy stopwatch uses `45 06`.

The pinned [hass-divoom Mini subclass](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/timeboxmini.py)
explicitly rejects countdown. Its `show_timer` is the stopwatch selector, not a
duration setter. The pinned [original Mini protocol](https://github.com/jbfuzier/timeboxmini/blob/64e3433a8e4c28933993aa581d596a1afe765e71/doc/protocol.md)
documents stopwatch `45 06` and scoreboard `45 07`, without a duration operation.
Production therefore retains the native countdown guard; no Evo countdown packet
is sent as an experiment.

Scoreboard updates carry two host-supplied integers, not elapsed-time or autonomous
decrement state. They might support a separately agreed host timer, as could the
already validated static-image countdown prototype. Such a timer would depend on
the host connection and must not silently replace native `countdown` behavior.
A Mini-specific duration capture or a verified primary implementation would
justify reopening native support.

On2026-10-19 the user chose to keep Mini countdown unsupported rather than add
an explicit foreground `--host` countdown. The earlier image countdown remains
a prototype, not a production fallback.

## Automatic model identification

The actual app's `p166s1.a.c.accept()` issues firmware queries `97 00`, `36` and
`37 00` only when its NewMode gate is true. Original Mini selects OldMode. The
`37` receiver derives hardware-family prefixes from 32-bit versions divided by
1000, but no verified original-Mini mapping or universal read path was found.
The [REvoom authors' product flags](https://divoom.2a03.party/pflags.html) confirm
Evo flag 21 and mark 20/22 as guesses; their [Mini page](https://divoom.2a03.party/devices/timebox-mini.html)
does not establish the missing Mini identity. Those update-family flags are not
the app-local model enum. Update or registration workflows are not discovery.

The standard SDP Device ID record was already absent on both available devices
after refresh. Bluetooth SIG [Device Information Service v1.2](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/DIS_v1.2/out/en/index-en.html)
defines optional read-only Model Number and PnP ID characteristics. Their presence
and association with these selected Classic endpoints have not been established.
They remain a conditional metadata lead, not an implemented classifier. Names,
MAC prefixes, RFCOMM channels, successful feature commands and timeouts are not
reliable model identity. Explicit CLI/config model overrides remain required.

## Provenance

The inspected official APK is Divoom Android 3.8.40, versionCode 640, SHA256
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`,
inspected with JADX 1.5.6. Decompiled copyrighted files stay outside Git.
Reproduction anchors: `DeviceFunction.DeviceTypeEnum.setDeviceMode`,
`DiscoverModel.s/o/t/r`, `CountDownFragment`, `ToolServer.k`, `CmdManager.s3`,
`p166s1.a.c.accept`, `p166s1.b.j`, and `u.h` firmware reply parsing.
