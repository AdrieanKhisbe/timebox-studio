# Evo persistent content investigation

Issue: [AdrieanKhisbe/timebox-studio#19](https://github.com/AdrieanKhisbe/timebox-studio/issues/19).
Research date: 2026-10-19. Scope: the existing Timebox Evo Classic/BLE consumer,
not the manufacturer's Wi-Fi/cloud/gallery products.

No storage command, display upload, delete, restart or device power cycle was
performed during this source-only investigation. Stored content was not replaced.
Separate parent-coordinated #8 tests selected existing tabs without uploads; see
[display-channel evidence](evo-display-channels.md). The table
separates source-established protocol candidates from actual Evo observations.
Persistence and enumeration on the user's Evo remain unverified.

## Capability table

| Capability | Protocol/source evidence | Actual Evo evidence | Current decision |
| --- | --- | --- | --- |
| Local SavedDesign | Repository `SavedDesign` / `DesignStore` are app-side JSON storage. | Not a device storage query. | Keep separate from device content IDs. |
| Static display upload | Existing `0x44` image encoder; manufacturer page289 calls this picture display. | Existing project baseline shows an arbitrary image. | Supported display operation; restart persistence is unknown. |
| Looping animation upload | Evo-specific implementation describes `0x49` frame chunks; manufacturer page290 gives total length and sequential chunks. | No restart comparison in this investigation. | Temporary playback is not evidence of a saved item. |
| Select custom/design channel | `45 05` has an Evo-specific encoder and independent golden packet. | Return from clock restored existing visible content in #8. | Channel selection, not stored-file enumeration or restart persistence. |
| Select design tab | hass-divoom sends custom channel then `BD 17 index`; actual Android app `CmdManager.q1(int)` emits the corresponding external command. | #8 fresh capability gate and visual tests confirmed indices0–2 with distinct existing artwork. | Supported bounded selection; not content IDs or persistence proof. |
| Numbered VJ effects | Evo-specific effect enum and `45 03 effect` fixtures. | Effect9 remained solid blue; effect0 had no positive validation in #8. | Typed VJ operations remain unsupported; these are not uploaded content IDs. |
| Save user GIF | Manufacturer page294 describes `B1` start/data/end with acknowledgement; page296 describes indexed `8C` upload. | Compatibility and restart persistence unverified. | No production storage writes. |
| Custom EQ/rhythm count | Manufacturer page295 and actual app request `B6 FF`; the app appends that many custom EQ entries after12 built-ins. Other B6 argument values delete an item. | No response captured from Evo. | EQ subset only; not general artwork/tab enumeration. Never scan parameters. |
| Enumerate file IDs | Manufacturer page298 describes `8E user_index` and paginated ID replies for a 64-pixel custom-image function. | It is not an Evo listing fixture; device/firmware support unknown. | Do not port a generic 64-pixel interface as Evo support. |
| Select existing content by file ID | No Evo-specific selection/identity correspondence established by these sources. | None. | Unsupported until verified independently of tab/effect indices. |

The [Evo-specific reference](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/PROTOCOL.md)
distinguishes display uploads from the app's multiple stored animations. Its
[custom-channel encoder](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/src/channels/custom.ts)
and [golden test](https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/test/channels/custom.spec.ts)
establish channel selection. They do not enumerate files. The
[hass-divoom design operation](https://github.com/d03n3rfr1tz3/hass-divoom/blob/479d728d1a414a8a9e880bd801fe5c4a6956df53/custom_components/divoom/devices/divoom.py)
is a multi-model implementation: its tab operation is a lead, not an Evo limit.

## Manufacturer Bluetooth leads

The official catalogue groups these pages under its Bluetooth protocol. The
catalogue is multi-device, so command presence does not prove support on Evo:

- [Picture display, page289](https://docin.divoom-gz.com/web/#/5/289)
- [Animation display, page290](https://docin.divoom-gz.com/web/#/5/290)
- [Save user GIF, page294](https://docin.divoom-gz.com/web/#/5/294)
- [Count/delete user GIF items, page295](https://docin.divoom-gz.com/web/#/5/295)
- [Indexed upload, page296](https://docin.divoom-gz.com/web/#/5/296)
- [Custom file ID information, page298](https://docin.divoom-gz.com/web/#/5/298)

Their readable JSON is served by
`https://docin.divoom-gz.com/server/index.php?s=/api/page/info&page_id=PAGE`.
Pages were retrieved directly on the research date. Do not confuse the same
site's Wi-Fi/cloud image-upload lists with a Classic RFCOMM device inventory.

The source-only custom EQ/rhythm count request candidate is `01 04 00 B6 FF B9 01 02`.
This fixture is calculated from the documented request, not captured hardware.
Do not replace `FF` with candidate indices: those request deletion.

For `8E`, the documented reply control1 carries a user index, total/offset/count
(as little-endian 16-bit values), then 32-bit file IDs; control2 ends the reply.
The wording explicitly refers to a 64-pixel custom-image function, so it cannot
supply an Evo parser or ID range without a compatible captured response.

Actual Divoom Android APK3.8.40 was available from the earlier alarm research
(SHA256 `d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`).
`CmdManager.q1(int)` sends the external use-user-define-index subcommand;
`CmdManager.u()` uses that same subcommand with the all-ones byte. These are app
code leads only: the code serves many device models, and the sentinel is not
assumed to be safe enumeration. Decompiled copyrighted source stays outside Git.

## Narrowing the count getter from the actual app

The same hash-verified APK3.8.40 provides the full consumer path:
`LightEqualizerFragment.standardLoad → LightViewModel.e → CmdManager.Q` sends
exactly `B6 FF`. The fragment first creates12 built-in EQ entries. The successful
B6 reply parser `u.h` posts its first data byte through `T1.i`; the fragment’s
`F2(count)` appends that many custom EQ entries. `showDelDialog` instead passes
`(position - 12) + 1` to `LightViewModel.i → CmdManager.a2`, a deletion operation.
Thus this count concerns the custom equalizer/rhythm subset, not arbitrary image/
GIF inventory, custom tabs, persistent content IDs or a storage capacity limit.

The request in `standardLoad` has no count-specific device gate. The create button
is gated to `PixooArch`, and higher-resolution products choose different built-in
thumbnails. Source reachability alone still does not prove Evo count support.
JADX reconstructed these handlers; it reported an unrelated reconstruction error
elsewhere in the fragment. Copyrighted decompiled source remains outside Git.

A future coordinated read would accept only a checksum-valid successful B6 reply
with exactly one unsigned count byte. No echoed query selector/nonce distinguishes
count from delete acknowledgements: exclusive fresh connection ownership is
required, with no competing or pending delete operations. Timeout means unknown,
not zero. Do not issue another B6 argument, retry as a scan, or infer file IDs.
The parent decided a physical count probe was unnecessary for this investigation;
no request, delete or other storage command was sent.

## Actual custom-tab save pipeline: destructive scope remains unverified

Source-only follow-up, 2026-10-19. No save packet or capability negotiation was
sent. Actual APK3.8.40 has a source-grounded selected-tab upload path, but it does
not establish a safe single-item append or recoverable production save API.

| Stage | Actual APK anchor | Established behavior |
| --- | --- | --- |
| Save button | `LightCustomFragment.onClick` / `Q2`, lines166–177,349–355 | `bt_make` passes the adapter’s entire list, `true`, and selected tab to `LightMakeNewModel.r`. |
| Tab scope | `LightMakeNewModel.r`, lines336–370; `CmdManager.P2`,792–815 | Image/animation save starts an upload with that tab index; it does not call ordinary `BD17` selection as the upload protocol. |
| Cache input | `LightMakeNewModel.o`,135–153; `p`,288–331; `u`,380–433 | Existing contents come from local `LightNewCustomBean` database rows keyed by Bluetooth address and tab, serialized as a JSON list of image blobs. A single new image may fill a vacant local list position; a full list defaults to position11. This is not device enumeration. |
| Start response | `u.h`,575–578; `LightMakeNewModel.onMessageEvent(T1.n)`,530–550 | A successful B1 reply posts the event which starts the image/animation upload path. |
| Upload | `LightMakeNewModel.v` / `y`,184–195,438–486 | Encode and concatenate valid cached items, send data chunks, send end, then update the local cache. |
| Legacy chunks | `p051f3.h.f`,171–203; `h.p`,269–272; `r.K`,449–465 | Legacy save uses control1 plus chunk lengthLE16 and native encoded bytes, at most200 bytes per default chunk, with40ms between writes. |
| End | `CmdManager.L0`,592–595 | End payload is exactly `B1 02` for legacy mode, or `8C 02` for newer mode; no appended tab or zero byte. |

Original `TimeboxEvo` model initialization resets `NewAniSendMode2020` off, and
its model branch does not directly enable it (`DeviceFunction`,738,836–884).
Thus the source default path is B1. It is not a universal firmware classifier:
`CmdManager.V`,948–950 sends external selector13, whose reply handler `u.i`,874–878
can enable the newer upload mode and change pacing. No selector13 negotiation
was performed here; unknown capability must not be silently treated as8C support.

Source-established legacy payload sequence, not a captured successful Evo save:

```text
B1 00 00 TAB                    start normal image/animation, selected tab
wait for checksum-valid 04 B1 55 success response
B1 01 CHUNK_LENGTH_LE16 BYTES    repeated data segments
B1 02                          end
```

For the newer path the start is `8C 00 TOTAL_LENGTH_LE32 TAB`. Its data segments
are `8C 01 TOTAL_LENGTH_LE32 CHUNK_INDEX_LE16 BYTES`, at most256 bytes; the app
calls this an index, increments by one, and uses that index to resend its cached
packet array (`LightMakeNewModel.t`,373–379; `h.f`,171–203). This should not be
silently reinterpreted as a byte offset. `u.h`,344–350 handles newer retransmit
requests with control1 and a16-bit index. The inspected start-trigger path is
still the successful B1 event above, so the complete8C handshake must be captured
before assuming how each firmware starts it.

The native image/animation container is produced by `h.g → h.h → h.c →
NDKMain.pixelEncode`, using frame count, speed, dimensions and optional text.
The app may adjust adjacent equal speeds before concatenation. Existing `0x44`
static display encoding is not thereby proven to be a drop-in storage blob.
[Manufacturer B1 documentation](https://docin.divoom-gz.com/web/#/5/294) says a data
unit must hold complete frame data, while the inspected app fragments its native
stream in200-byte segments. The [newer8C documentation](https://docin.divoom-gz.com/web/#/5/296)
also differs in terminology. Resolve these differences with frozen app/capture
fixtures, not speculative production code.

A B1 success reply carries no echoed stage, tab, nonce or request ID. The app
bulk-sends chunks/end and then saves its local database; that local success is
not independent readback of device storage or persistence. Timeout, reconnect
and partial-upload behavior are not established. A failed start/end cannot be
safely retried as if idempotence were proven.

**Bounded next step:** a reviewed throwaway prototype may investigate explicit
whole-tab replacement, only after the user designates one disposable tab and
backs up its original items in the official app. Treat the entire selected tab
as replaceable: the app rebuilds a cached tab list and there is no verified safe
append or device-side backup/readback. Confirm mode negotiation and native blob
fixtures before any write; announce all packets; preserve the other tabs; use
exclusive fresh connection ownership. Observe selected-tab contents before and
after, then separately obtain restart approval to test persistence. No production
`saveContent`, list, delete or overwrite API is implemented. These source facts
justify proposing that constrained investigation for review, not marking save
support verified or automatically publishing an implementation ticket.

Reproduction: use JADX1.5.6 `--single-class` on the hash-verified APK stated above
for `com.divoom.Divoom.view.fragment.light.common.LightCustomFragment`,
`com.divoom.Divoom.view.fragment.light.model.LightMakeNewModel`,
`com.divoom.Divoom.bluetooth.CmdManager`, `com.divoom.Divoom.bluetooth.u`,
`com.divoom.Divoom.bluetooth.r`, and `p051f3.h`. Copyrighted source remains outside
Git. Exact scratch-output SHA256 checksums (not upstream source-file hashes):

| Class output | SHA256 |
| --- | --- |
| `LightCustomFragment` | `c4b6c218687c9b77dce808ba153224fa2f2d987108018195b2b3266561e77eec` |
| `LightMakeNewModel` | `12348fca730356f6d21afd362e6b70c0af4e2d6c5c6bf1c1786eac8531d23f8d` |
| `CmdManager` | `510037ffe270a6280d6f45837a242bf43f918262f261448f80e8843ffd9e9677` |
| `u` | `fa067bf6598e06668a5abb74e1a7aeb5bce2f01b1a352f248e91e0957fa58c7c` |
| `p051f3.h` | `83125170ef2dc60146e94f87a540c3acfb28f9b2623c0a2192d4f48d7a9ffba9` |

## Outstanding validation and proposed follow-ups

There is no verified new capability ready for an implementation ticket yet.
The investigation remains open for physical evidence; do not mark the table's
candidates as supported or Ready. Before changing content, a human should identify
a designated disposable test slot and record current custom-channel contents.
No existing user artwork may be overwritten as implicit exploration.

1. Capture model/firmware and app behavior while selecting existing custom tabs,
   without editing/deleting/uploading. Record tab IDs separately from content IDs.
2. If a future scoped EQ investigation needs the exact count request, capture its response with
   the strict receive framing from [AdrieanKhisbe/timebox-studio#11](https://github.com/AdrieanKhisbe/timebox-studio/issues/11).
   Do not probe other `B6` values. An EQ count alone is not an artwork list.
3. Establish a device-specific safe enumeration request from app/capture evidence
   before attempting the generic `8E` lead. Preserve unknown fields and validate
   complete multipart replies; no fabricated IDs.
4. With explicit storage-write/restart approval and a designated slot, compare a
   normal display upload and an app-saved custom item after disconnect, reconnect,
   and restart. Record observations, power state and commands; transport success
   cannot establish persistence.

If verified, propose separate follow-up tickets (review before Ready):

- Library `listStoredContent()`; CLI `content list`; REPL `content list` — only
  when safe enumeration, ID semantics and complete responses are captured.
- Library `selectStoredContent(id:)`; CLI/REPL `content show ID` — only when an
  actual content ID selects an existing item without replacing it.
- Library `saveContent(_:to:)`; CLI/REPL `content save FILE --slot SLOT` — requires
  a proven save protocol, acknowledgement/retry rules, slot ownership and explicit
  overwrite behavior. It is a separate change from temporary `image`/animation.

Each future ticket must cite its capture/fixture, model/firmware, limits,
[AdrieanKhisbe/timebox-studio#19](https://github.com/AdrieanKhisbe/timebox-studio/issues/19),
receive prerequisites and automated/manual acceptance tests, then be added to the
public project. No follow-up was published because the evidence gate is unmet.
