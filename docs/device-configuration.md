# Device configuration

`timeboxctl list` lists paired Timeboxes, including their audio-named Classic
endpoints. `--all` also displays other paired Bluetooth devices. Listing never
connects to a device and takes no target selector.

`timeboxctl list --save` saves all discovered Timeboxes without a prompt in
`~/.config/timebox-studio/config.yml`. Use `--config PATH` to choose another file
for discovery saving or device commands. Even with `--all`, only Timeboxes are
saved. Rename/default-selection hints are printed on stderr.

```yaml
default: desk
devices:
  desk:
    mac: "AA:BB:CC:DD:EE:01"
    bluetooth_name: "Timebox-Evo-audio"
```

Logical names are independent of Bluetooth names. Saves merge by MAC identity,
retain offline entries, and refresh Bluetooth metadata without renaming existing
logical names. New name collisions receive a MAC suffix. An existing default is
preserved; otherwise the first logical name in deterministic sorted order is used.

Device commands accept case-insensitive `--device NAME` (alias `--name`) or
`--address MAC`, never both. Selection order is explicit selector, `TIMEBOX_ADDRESS`,
config default, then the sole discovered Timebox. A selected offline device fails
explicitly without falling back. Ordinary macOS commands use Classic RFCOMM and
that device's SDP channel; `--channel` overrides it.

The CLI uses Yams to validate YAML and locate nodes, then edits only affected
source tokens. Comments, unknown fields, order and untouched formatting survive.
Block and flow mappings and quoted/single-line config values are supported for
editing. Complex edited scalars (for example anchors or multiline block scalars)
fail explicitly before saving rather than losing source content. Unknown multiline
fields are retained. Duplicate names (ignoring case), duplicate MAC identities,
invalid addresses and dangling defaults are rejected. Writes validate the result
and use an atomic replacement; malformed files are never silently repaired.

Manage logical names and the saved default without connecting to Bluetooth:

```sh
timeboxctl device select desk
timeboxctl device rename desk office
timeboxctl device select             # interactive, Enter accepts current default
timeboxctl device rename             # interactive device and new-name prompts
timeboxctl config show               # original YAML bytes including comments
timeboxctl config show --yml         # --yaml alias
timeboxctl config show --json        # plain config object, including unknown fields
```

All commands honor `--config PATH`. Missing interactive arguments with redirected
stdin fail immediately. `q` or EOF cancels selection; EOF cancels the new-name
prompt. Invalid input leaves the file unchanged. Renaming updates a default
reference and preserves the entry's Bluetooth name and annotations. Empty names
and collisions ignoring case are errors. `config show` fails if no file exists;
JSON and YAML flags are mutually exclusive. YAML values without a JSON
representation produce an explicit error for JSON output.
