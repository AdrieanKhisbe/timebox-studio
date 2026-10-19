# Evo persistent content investigation

Issue: [AdrieanKhisbe/timebox-studio#19](https://github.com/AdrieanKhisbe/timebox-studio/issues/19).
Research date: 2026-10-19. Scope: the existing Timebox Evo Classic/BLE consumer,
not the manufacturer's Wi-Fi/cloud/gallery products.

No storage command, display upload, delete, restart or device power cycle was
performed during this investigation. Device content was not changed. The table
separates source-established protocol candidates from actual Evo observations.
Persistence and enumeration on the user's Evo remain unverified.

## Capability table

| Capability | Protocol/source evidence | Actual Evo evidence | Current decision |
| --- | --- | --- | --- |
| Local SavedDesign | Repository `SavedDesign` / `DesignStore` are app-side JSON storage. | Not a device storage query. | Keep separate from device content IDs. |
| Static display upload | Existing `0x44` image encoder; manufacturer page289 calls this picture display. | Existing project baseline shows an arbitrary image. | Supported display operation; restart persistence is unknown. |
| Looping animation upload | Evo-specific implementation describes `0x49` frame chunks; manufacturer page290 gives total length and sequential chunks. | No restart comparison in this investigation. | Temporary playback is not evidence of a saved item. |
| Select custom/design channel | `45 05` has an Evo-specific encoder and independent golden packet. | Current tab retention not physically rechecked. | Channel selection, not stored-file enumeration. |
| Select design tab | hass-divoom sends custom channel then `BD 17 index`; actual Android app `CmdManager.q1(int)` emits the corresponding external command. | Evo-supported tab range, numbering and retention unknown. | Do not expose arbitrary byte IDs as verified Evo support. |
| Numbered VJ effects | Evo-specific effect enum and `45 03 effect` fixtures. | No new physical observations. | Built-in display selection, not uploaded content IDs. |
| Save user GIF | Manufacturer page294 describes `B1` start/data/end with acknowledgement; page296 describes indexed `8C` upload. | Compatibility and restart persistence unverified. | No production storage writes. |
| Item count | Manufacturer page295 describes `B6 FF` returning a count. Other parameter values delete an item. | No response captured from Evo. | Candidate read-only investigation only; never scan parameters. |
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

The source-only count request candidate is `01 04 00 B6 FF B9 01 02`.
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

## Outstanding validation and proposed follow-ups

There is no verified new capability ready for an implementation ticket yet.
The investigation remains open for physical evidence; do not mark the table's
candidates as supported or Ready. Before changing content, a human should identify
a designated disposable test slot and record current custom-channel contents.
No existing user artwork may be overwritten as implicit exploration.

1. Capture model/firmware and app behavior while selecting existing custom tabs,
   without editing/deleting/uploading. Record tab IDs separately from content IDs.
2. If the Evo actually accepts the exact count request, capture its response with
   the strict receive framing from [AdrieanKhisbe/timebox-studio#11](https://github.com/AdrieanKhisbe/timebox-studio/issues/11).
   Do not probe other `B6` values. A count alone is not a list.
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
