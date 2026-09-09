# tessera

Config-driven window management for [Hammerspoon](https://www.hammerspoon.org/). A
half-screen app switcher plus named full-desktop layout profiles, both placing
windows into geometry-based "slots".

## Install

Clone into your Hammerspoon config directory:

```sh
git clone git@github.com:madebygrant/tessera.git ~/.hammerspoon/tessera
```

Create your local config from the template — either outside the repo (preferred,
survives re-cloning) or inside it:

```sh
# outside, beside your init.lua
cp ~/.hammerspoon/tessera/tessera-config.example.lua ~/.hammerspoon/tessera-config.lua

# or inside the repo (gitignored)
cp ~/.hammerspoon/tessera/tessera-config.example.lua ~/.hammerspoon/tessera/config.lua
```

Edit it for your machine: screen names, apps, slots, keys, profiles. It's data
only, so there's no code in there to keep in sync. Either location stays out of
version control, and tessera loads whichever it finds — the outside one wins if
both exist, and it says so on load.

Then load it from `~/.hammerspoon/init.lua`:

```lua
require("tessera")
```

Reload Hammerspoon (menu bar → Reload Config, or `hs.reload()`).

## Concepts

- **Slots** are fractions of a screen, not pixels: `{ screen, x, y, w, h }` in
  `0..1` of that screen's frame. Resolution-independent; a missing monitor falls
  back to the primary screen.
- **Profiles** are named full-desktop layouts, each bound to its own hotkey.
- **Switcher** pins an anchor app to half the screen and cycles other apps
  through the remaining half via `keys.switcher`+`1..N` / `Left`/`Right`. Its hotkeys
  are global, but its targets belong to the active profile — pressing a
  profile's hotkey retargets the switcher along with the layout. A profile's
  `start` picks which app it opens on without changing the number-key order.
- **Slot move** (optional) sends whatever window has focus to the Nth slot of
  the active profile, so apps tessera knows nothing about still land somewhere
  sane.
- **Keys** are declared together in `config.keys`, one layer per feature, so a
  clash is visible before you hit it.
- **screenInsets** carve pixels off a screen before slots compute (e.g. clearing
  a Sketchybar overlay macOS doesn't report).
- **gap** shrinks every slot edge by N px so neighbours sit apart.
- **Sketchybar readout** (optional) reports the active profile and slot number
  to a [SketchyBar](https://github.com/FelixKratz/SketchyBar) item.

## Hotkeys

All four layers are declared together in `config.keys`, since the way they break
is by colliding with each other or with an app. The switcher layer is bound once
and never rebinds; only what it targets changes with the active profile.

| Keys | Action |
| --- | --- |
| `ctrl+alt`+`1..N` | Jump to the Nth app of the active profile |
| `ctrl+alt`+`Left`/`Right` | Cycle through them |
| `ctrl+alt`+`F` | Toggle the current app full-screen |
| `ctrl+alt+cmd`+profile key | Apply that profile's layout |
| `ctrl+alt+shift`+`1..N` | Send the focused window to the Nth slot (optional) |

Number keys are bound for the widest `apps` list across all profiles, so a key
past the active profile's count does nothing rather than wrapping.

`ctrl+alt` deliberately avoids `alt+cmd`, where the arrows are tab-switch in
most browsers and terminals. Hammerspoon wins that fight and would break them
with no error. The trade-off is VoiceOver, which claims `ctrl+alt` as its own
modifier: while it is on, the switcher keys silently do nothing.

## Files

| File | Role |
| --- | --- |
| `init.lua` | Package entry point (`require("tessera")`). Loads the feature modules. |
| `tessera-config.example.lua` | Template config — copy to one of the two config locations. |
| `../tessera-config.lua` *or* `config.lua` | Your local config — screens, slots, insets, gap, apps, keys, profiles. |
| `layout-shared.lua` | Pure engine: geometry resolution, frame clamp, window registry. |
| `schema.lua` | Config accessors and the feature-flag rule, attached at load. |
| `layout-workspace.lua` | The half-screen app switcher. |
| `window-layout.lua` | Applies a profile on its hotkey. |
| `slot-move.lua` | Optional: sends the focused window to a slot of the active profile. |
| `sketchybar/` | Optional bar item and plugin, to copy into your SketchyBar config. |

## Configuration

Everything lives in your config file (copied from
`tessera-config.example.lua` — see Install for the two locations).

- **New app** — add to `config.apps` (`{ app=, titleSuffix?, profileDir?, launch? }`).
- **New slot** — add to `config.slots` (fractions of a screen).
- **Keys** — `config.keys` holds all four layers (`switcher`, `slotMove`,
  `profile`, `maximize`) and is required; tessera says so at load if it's
  missing. A profile can carry its own `modifier` to sit off the shared one.
- **New profile** — add to `config.profiles` with a `key`; it auto-binds on
  `config.keys.profile`. `place` order matters, since earlier entries reserve
  their window first. Each profile also needs a `switcher` block (`anchor`,
  `anchorSlot`, `otherSlot`, `fullSlot`, `apps`, optional `start`) saying what
  the switcher hotkeys drive while that profile is active. An optional `slots`
  list fixes the slot-move key order. `config.defaultProfile` picks the one used
  at load.

Optional features follow one rule: the config block has to be present, and
`enabled = false` inside it turns the feature off. No block means off, so your
config file lists everything that runs.

- **Slot move** — `config.slotMove` binds `keys.slotMove`+`1..N` to the active
  profile's slots. Key order is that profile's optional `slots` list, and
  otherwise the slots its `place` entries name, first appearance winning. Pin it
  explicitly if reordering `place` shouldn't move your keys around. Keys bind
  for the longest list across all profiles, so a key past the active profile's
  count does nothing.
- **Sketchybar** — `config.sketchybar` turns on the bar readout. See below.

Screen names are machine-specific. On a new machine, list them with:

```sh
hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'
```

and update `config.screens`. Unmatched names fall back to the primary screen.

## Sketchybar readout

Optional. tessera fires a [SketchyBar](https://github.com/FelixKratz/SketchyBar)
event whenever the switcher moves, so a bar item can show where you are:

```
 SPLIT 2/2
```

```lua
C.sketchybar = {
  enabled = true,
  event   = "tessera_switcher",
}
```

`event` must match the `--add event` name in your bar config, and an optional
`bin` overrides the binary path (unset searches both Homebrew prefixes). A
machine without sketchybar is a no-op either way.

The bar half ships in `sketchybar/`. Copy it into your SketchyBar config, or
symlink it so repo updates land automatically:

```sh
ln -s ~/.hammerspoon/tessera/sketchybar/items/tessera.sh   ~/.config/sketchybar/items/tessera.sh
ln -s ~/.hammerspoon/tessera/sketchybar/plugins/tessera.sh ~/.config/sketchybar/plugins/tessera.sh
```

Then source the item from your `sketchybarrc`:

```sh
source "$ITEM_DIR/tessera.sh"
```

The label uses white unless you export `TESSERA_LABEL_COLOR` from your own bar
config. Writing a different item instead is fine; each trigger carries:

| Variable | Value |
| --- | --- |
| `PROFILE` | Active profile name |
| `APP` | Config ref of the current cycled app (`terminal`) |
| `APP_NAME` | Its macOS app name, for matching against `front_app` |
| `ANCHOR_NAME` | The anchor's app name |
| `INDEX` / `COUNT` | Position in the profile's `apps` list |
| `MAXIMIZED` | Whether it covers the anchor |
| `FOCUSED` | True when tessera just pulled that app forward |

`FOCUSED` matters if the item hides the slot number outside the layout: a
profile retarget places nothing, so it must not claim the front app.

