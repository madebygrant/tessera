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

Edit it for your machine (screen names, apps, slots, profiles). Either location
stays out of version control. tessera loads whichever it finds — the outside one
wins if both exist, and it says so on load.

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
  through the remaining half via `modifier`+`1..N` / `Left`/`Right`. Its hotkeys
  are global, but its targets belong to the active profile — pressing a
  profile's hotkey retargets the switcher along with the layout.
- **screenInsets** carve pixels off a screen before slots compute (e.g. clearing
  a Sketchybar overlay macOS doesn't report).
- **gap** shrinks every slot edge by N px so neighbours sit apart.

## Files

| File | Role |
| --- | --- |
| `init.lua` | Package entry point (`require("tessera")`). Loads the feature modules. |
| `tessera-config.example.lua` | Template config — copy to one of the two config locations. |
| `../tessera-config.lua` *or* `config.lua` | Your local config — screens, slots, insets, gap, apps, switcher, profiles. |
| `layout-shared.lua` | Pure engine: geometry resolution, frame clamp, window registry. |
| `layout-workspace.lua` | The half-screen app switcher. |
| `window-layout.lua` | Applies a profile on its hotkey. |

## Configuration

Everything lives in your config file (copied from
`tessera-config.example.lua` — see Install for the two locations).

- **New app** — add to `config.apps` (`{ app=, titleSuffix?, profileDir?, launch? }`).
- **New slot** — add to `config.slots` (fractions of a screen).
- **New profile** — add to `config.profiles` with its own `modifier`+`key`; it
  auto-binds. `place` order matters — earlier entries reserve their window first.
  Each profile also needs a `switcher` block (`anchor`, `anchorSlot`,
  `otherSlot`, `fullSlot`, `apps`) saying what the switcher hotkeys drive while
  that profile is active. `config.defaultProfile` picks the one used at load.

Screen names are machine-specific. On a new machine, list them with:

```sh
hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'
```

and update `config.screens`. Unmatched names fall back to the primary screen.
