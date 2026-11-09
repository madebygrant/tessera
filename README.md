# tessera

Window layouts for [Hammerspoon](https://www.hammerspoon.org/), driven by one
config file. A switcher keeps an anchor app on one half of the screen and cycles
other apps through the other half. Profiles place every app at once on one key.
Both put windows into "slots", rectangles measured in fractions of a screen.

## Install

Clone into your Hammerspoon config directory:

```sh
git clone git@github.com:madebygrant/tessera.git ~/.hammerspoon/tessera
```

Copy the template. Outside the repo is better, because it survives a re-clone:

```sh
# beside your init.lua
cp ~/.hammerspoon/tessera/tessera-config.example.lua ~/.hammerspoon/tessera-config.lua

# or inside the repo (gitignored)
cp ~/.hammerspoon/tessera/tessera-config.example.lua ~/.hammerspoon/tessera/config.lua
```

Edit it for your machine: screen names, apps, slots, keys and profiles. It's
plain data with no code in it. If both files exist, tessera uses the one outside
the repo and prints which it picked.

Load it from `~/.hammerspoon/init.lua`:

```lua
require("tessera")
```

Then reload Hammerspoon from the menu bar, or run `hs.reload()`. After any edit,
`./check.sh` loads every file and validates your config inside the running
Hammerspoon.

Hammerspoon needs Accessibility permission, and it can drop across a reboot.
tessera alerts once when it's missing, and every key does nothing until it's
back. The toggle in System Settings can show on while the permission is stale.
In that case run `tccutil reset Accessibility org.hammerspoon.Hammerspoon`,
grant the prompt, then quit and reopen Hammerspoon. A reload isn't enough.

## Concepts

- **Slots** are `{ screen, x, y, w, h }` in fractions (0 to 1) of a screen, so
  they survive a resolution change. A slot on a missing monitor lands on the
  primary screen.
- **Profiles** are full-desktop layouts, each on its own hotkey. Applying one
  moves every app it names into its slot and launches any that aren't running.
- **The switcher** belongs to the active profile. Its keys bind once, and a
  profile hotkey changes what they drive. A profile's `start` picks the app it
  opens on without changing the number-key order.
- **Profiles remember screens.** tessera saves the last profile per screen setup
  and restores it at load. A profile can list the `screens` it needs, and on
  dock or undock tessera returns to the last profile you used with those
  screens. With nothing saved, it picks a fitting profile that needs the most
  screens, so a docked layout beats a laptop one while the monitor is in.
- **Slot move** (optional) sends the focused window to a slot of the active
  profile, for apps tessera doesn't know about.
- **The overlay** (optional) draws the active profile's slots and their keys on
  screen while you hold the switcher or slot-move modifiers on their own.
- **screenInsets** take pixels off a screen edge before tessera computes slots,
  for overlays macOS doesn't report, like SketchyBar.
- **gap** takes N px off every slot edge, so neighbours end up 2N apart.

## Hotkeys

Every key layer lives in `config.keys`, because they break by colliding with
each other or with an app.

| Keys | Action |
| --- | --- |
| `ctrl+alt`+`1..N` | Switch to the Nth app of the active profile |
| `ctrl+alt`+`Left`/`Right` | Cycle through them |
| `ctrl+alt`+`F` | Toggle the current app between its half and the full screen |
| hold `ctrl+alt` | Show the switcher overlay |
| `ctrl+alt+cmd`+profile key | Apply that profile |
| `ctrl+alt+shift`+`1..N` | Send the focused window to the Nth slot |
| hold `ctrl+alt+shift` | Show the slot-move overlay |

Number keys bind for the longest `apps` list across all profiles. A key past the
active profile's count does nothing.

The switcher uses `ctrl+alt` to stay off `alt+cmd`, whose arrows switch tabs in
most browsers and terminals. Hammerspoon gets those keys first and would break
them with no error. The cost is VoiceOver, which also uses `ctrl+alt`. While
VoiceOver is on, the switcher keys do nothing.

## Files

| File | Role |
| --- | --- |
| `init.lua` | Entry point (`require("tessera")`). Loads the config and the feature modules. |
| `tessera-config.example.lua` | The template config. |
| `../tessera-config.lua` *or* `config.lua` | Your config: screens, slots, insets, gap, apps, keys, profiles. |
| `schema.lua` | Config accessors, load-time validation, profile choice, the feature-flag rule. |
| `layout-shared.lua` | Geometry, the frame clamp, app and window lookup, the window registry. |
| `layout-workspace.lua` | The switcher. |
| `window-layout.lua` | Applies a profile, and re-applies on dock or undock. |
| `slot-move.lua` | Optional. Sends the focused window to a slot. |
| `overlay.lua` | Optional. The hold-to-show slot overlay. |
| `sketchybar/` | Optional bar item and plugin for your SketchyBar config. |
| `check.sh` | Loads every file and validates each config present. |

## Configuration

Everything goes in your config file.

- **New app.** Add it to `config.apps` (`{ app=, titleSuffix?, profileDir?, launch? }`).
- **New slot.** Add it to `config.slots`, in fractions of a screen.
- **Keys.** `config.keys` needs `switcher`, `slotMove`, `profile` and
  `maximize`, and tessera errors at load if one is missing. A profile can set its
  own `modifier`.
- **New profile.** Add it to `config.profiles` with a `key`. Order in `place`
  matters, because earlier entries claim their window first. Each profile needs
  a `switcher` block (`anchor`, `anchorSlot`, `otherSlot`, `fullSlot`, `apps`,
  optional `start`). `slots` fixes slot-move's key order and `screens` names the
  monitors it needs; both are optional. `config.defaultProfile` is the one used
  on first run.
- **launchAtLoad.** Set it to `false` to stop a reload opening apps that aren't
  running. Load never takes focus either way.

tessera checks every profile at load, so a typo in an app or slot name fails on
reload rather than on a keypress.

Optional features follow one rule. The config block has to exist, and
`enabled = false` inside it turns the feature off. No block means off.

- **slotMove** binds `keys.slotMove`+`1..N`. Key order is the profile's `slots`
  list, else the slots its `place` entries name, in order. Set `slots` if
  reordering `place` shouldn't move your keys.
- **overlay** takes `delay`, the seconds to hold before it shows (default 1).
- **sketchybar** turns on the bar readout, below.

Screen names differ per machine. List yours with:

```sh
hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'
```

and put them in `config.screens`. Names that don't match fall back to the
primary screen.

When the keys go quiet, `hs -c 'print(require("tessera").status())'` prints the
active profile, switcher index, Accessibility state, pending launches and the
window tracked for each app.

## Sketchybar readout

Optional. tessera fires a [SketchyBar](https://github.com/FelixKratz/SketchyBar)
event on every switch, so a bar item can show where you are:

```
NETRUNNER / GHOSTTY
```

The app name only shows while you're in the layout's apps. Scrolling on the item
cycles them.

```lua
C.sketchybar = {
  enabled = true,
  event   = "tessera_switcher",
}
```

`event` must match the `--add event` name in your bar config. `bin` overrides the
binary path; unset, tessera checks both Homebrew prefixes. Without sketchybar
installed, nothing happens.

Copy `sketchybar/` into your SketchyBar config, or symlink it so updates arrive
with `git pull`:

```sh
ln -s ~/.hammerspoon/tessera/sketchybar/items/tessera.sh   ~/.config/sketchybar/items/tessera.sh
ln -s ~/.hammerspoon/tessera/sketchybar/plugins/tessera.sh ~/.config/sketchybar/plugins/tessera.sh
```

Then source the item from your `sketchybarrc`:

```sh
source "$ITEM_DIR/tessera.sh"
```

Three variables, exported from your bar config, change how it looks:

| Variable | Effect |
| --- | --- |
| `TESSERA_LABEL_COLOR` | Profile colour. White if unset. |
| `TESSERA_APP_COLOR` | App name colour. Matches the profile if unset. |
| `TESSERA_HIDE_ITEMS` | Space-separated items to hide once tessera has a profile, like a front-app readout it replaces. |

To write your own item instead, each trigger carries:

| Variable | Value |
| --- | --- |
| `PROFILE` | Active profile name |
| `APP` | Config ref of the current cycled app (`terminal`) |
| `APP_NAME` | Its macOS app name, for matching against `front_app` |
| `ANCHOR_NAME` | The anchor's app name |
| `INDEX` / `COUNT` | Position in the profile's `apps` list |
| `MAXIMIZED` | Whether it covers the anchor |
| `FOCUSED` | True when tessera just pulled that app forward |

`FOCUSED` matters if your item hides the app outside the layout. A profile
change places nothing, so it must not claim the front app.
