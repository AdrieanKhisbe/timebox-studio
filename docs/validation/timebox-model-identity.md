# Mini/Evo model identity investigation

Issue: [AdrieanKhisbe/timebox-studio#20](https://github.com/AdrieanKhisbe/timebox-studio/issues/20).
Date: 2026-10-19. No device connection or packet was sent by this investigating
agent. Parent-coordinated SDP and display observations are identified separately.

## Conclusion

No trustworthy automatic Mini/Evo classifier is established. Verified RFCOMM
channels 4 and 1 identify working control endpoints on the two tested units, not
model identity. Name-based app routing, firmware version numbers and a modern
cloud-registration query do not repair that gap. Explicit or saved model
overrides remain the correct supported path for renamed AKTBR.

The next standard read-only evidence is the SDP Device Identification record
(UUID 1200), including vendor-source/vendor/product/version. Cached lookups on
both units returned no record; the parent reported those results. A cache miss
is not evidence of absent device support. The parent subsequently ran the bounded standard SDP refresh on both devices.
Each completed successfully (request 0/callback 0), reported seven service records,
and returned no UUID 1200/PnP record. This establishes that the refreshed records
available through this API on these two units did not expose the candidate
identity fields; it is not a claim that every Divoom firmware lacks identity.
The [redacted refresh results](fixtures/mini-evo-sdp-identity.json) are transcribed
from the parent’s reported command output.

## Actual app evidence

The inspected publisher app is APK3.8.40, versionCode 640, SHA256
`d7ae490205cf71cc37f74948bd1ca7f1b2a446070565294b3ae835c0a51fde81`.
Acquisition, independent inventory match, tool versions and copyright handling
are documented in the [existing APK provenance report](evo-finite-weekday-follow-up.md#actual-apk-acquisition-and-control-flow).
JADX 1.5.6 decompiled the classes below into ignored `/private/tmp` files; no
copyrighted binary or decompiled class is committed.

| Actual class/method | Evidence | Identity implication |
| --- | --- | --- |
| `DeviceFunction.DeviceTypeEnum` | Defines original Mini type 1 and original Evo type 3 among many app-local types. | Enum numbers are not automatically device reply codes. |
| Same, `setDeviceModel(String)` | Routes name prefixes, including TimeBox-mini and TimeBox-Evo, with a fallback to the normal Timebox type. It separately recognizes a differently cased newer Evo prefix. | Renameable names and fallback/case rules cannot reliably identify AKTBR. |
| `bluetooth.r.s(BluetoothDevice)` | Calls the name-based model setter when connecting. | This app path does not provide independent manufacturer/product identity. |
| `bluetooth.j.c.onLeScan(...)` | Receives advertising bytes but its runnable uses device names/addresses/paired history rather than parsing a model discriminator from those bytes. | Inspected callback is not an advertising identity parser. |
| `bluetooth.CmdManager.B(int)` / `u.h(...)` | Firmware query 0x97; reply selector0 carries a 16-bit firmware number. | Firmware version alone has no verified Mini/Evo product mapping. |
| `CmdManager.y()` / external enum | Sends `BD 2B 00`, named GET_DEVICE_INFO. | Name looks useful, but the receiving path must be traced. |
| `bluetooth.u.i(...)` / `g.v(...)` | Dispatches BD2B to parsing deviceID/password/type/subtype and cloud-registration state. | Not a demonstrated Mini/Evo model response. |
| `bluetooth.g.l()` / `DeviceFunction.setDeviceMode(...)` | Requests BD2B only when a feature flag is set; flag resets false and stays false in originalMini and Evo branches, while LCD/highpixel branches enable it. | This modern query is not an established identity path for the original Mini/Evo. |

The modern registration response's type byte must not be interpreted as the
app-local Mini/Evo types 1/3 enumeration without a verified mapping. No BD2B, speculative
identity opcode, firmware update or cloud-registration request was sent.

## Standard passive metadata path

The Bluetooth SIG [Device Identification Profile](https://www.bluetooth.com/specifications/specs/device-id-profile-1-2/)
specifies device identity information exported as SDP records. Its
[assigned numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html)
and the local Apple SDK `BluetoothAssignedNumbers.h` identify:

| Service / attribute | Meaning |
| --- | --- |
| Service UUID 0x1200 | PnP/Device Identification record |
| 0x0200 | Specification identifier |
| 0x0201 | Vendor identifier |
| 0x0202 | Product identifier |
| 0x0203 | Product version |
| 0x0204 | Primary record flag |
| 0x0205 | Vendor identifier source |

Apple's [getAttributeDataElement](https://developer.apple.com/documentation/iobluetooth/iobluetoothsdpservicerecord/getattributedataelement(_:))
provides access. The current production inspector lists generic service names,
RFCOMM channels, handles and counts, but omits these identity fields. The prepared
scratch capture performs a single standard SDP query with an 8-second bound and
collects all matching PnP records; it makes no RFCOMM, control, pairing, rename,
clock or storage calls. Missing/error/timeout evidence stays explicitly unknown.

Even distinct product IDs on the two units would initially be candidate
fingerprints. Establish vendor-source correctness, manufacturer/model mapping,
primary-record conflicts, firmware variants and endpoint association before
shipping an automatic classifier. A shared chipset vendor/product record may
identify a module rather than the retail Divoom model. Never classify every
paired speaker or a stale cache entry as a Timebox.

## Next safe tests and decisions

1. Parent inspected/ran the standard SDP refresh sequentially on the selected
   Evo and Mini. Both successful refreshes exposed no PnP identity record.
   No display probe or target-selection change was required.
2. If meaningful identity records exist, compare all records and corroborate
   vendor/product mapping with manufacturer or independently model-identified
   captures. Add classifier fixtures only after that evidence exists.
3. If no useful record exists, retain explicit/config selection and record the
   available evidence as insufficient. Do not replace it with names, MAC prefix,
   channel numbers, successful display writes or undocumented opcode sweeps.

A Bluetooth-name-based discovery convenience remains distinct from a trustworthy
model classifier. Extending renamed-device automatic list/save still requires
passive identity evidence. Automatic connection-dependent identification must
not select a different target or send alternate display encodings to guess.
