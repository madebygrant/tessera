# tessera — Hammerspoon window layout

Config-driven window management: a half-screen app switcher plus named
full-desktop layout profiles, both placing windows into geometry-based "slots".

Loaded from `~/.hammerspoon/init.lua` via `require("tessera")`, which resolves to
`tessera/init.lua` and wires up the two feature modules. Reload after edits:
menu-bar Hammerspoon → Reload Config (or `hs.reload()`).

## Files

- **init.lua** — package entry point (`require("tessera")`). Loads the two
  feature modules in order; returns the config table.
- **config.lua** — the ONE file to edit. Screens, slots, insets, gap, apps,
  the switcher, and layout profiles. Everything below reads from here.
- **layout-shared.lua** — pure engine: screen/geometry resolution
  (`frameFor`, `resolveScreen`), the frame clamp (`setFrameClamped`), the
  cross-module window registry (`publishWindow`/`window`), `entryKey`, `endsWith`.
  No config knowledge.
- **layout-workspace.lua** — the half-screen switcher. Pins `switcher.anchor`
  to `anchorSlot`; hotkeys cycle `switcher.apps` through `otherSlot`
  (`modifier`+1..N, and `modifier`+Left/Right). Publishes each placed window to
  the registry.
- **window-layout.lua** — applies a `config.profiles` entry on its hotkey:
  each app → its slot, launching/matching via the app's config.

## Key concepts

- **Slots are fractions of a screen**, not pixels: `{ screen, x, y, w, h }` in
  0..1 of that screen's `:frame()`. Resolution-independent; a missing monitor
  falls back to the primary screen. Resolved live via `config.slot(name)`.
- **screenInsets** carve pixels off a screen before slots compute — used to
  clear overlays macOS doesn't report (Sketchybar: `external = { top = 28 }`).
- **gap** shrinks every slot edge by N px (neighbours end up `2*gap` apart).
  Currently `0` (flush, edge-to-edge).
- **Window registry** decouples the two feature files: the switcher publishes
  its placed windows by `entryKey(app, titleSuffix)`; window-layout reuses the
  exact same window for a profile entry marked `useSwitcherWindow = true`.
  Neither file requires the other.
- **Clamp** (`setFrameClamped`) only pulls a window back from its screen's RIGHT
  edge (stops apps snapping wider and bleeding onto the side-by-side laptop). It
  deliberately does NOT clamp vertically, so a too-tall window overflows off the
  bottom screen edge instead of being pushed up into the row above. Runs at 0 /
  0.15s / 0.4s to catch apps that resize a beat after `setFrame` (Ghostty).

## Gotchas

- **Ghostty** snaps to a cell grid, so a window can land a few px larger than
  its slot; the clamp + off-bottom overflow handle it. Its `title` config is
  GLOBAL to the instance, so you can't title-match to tell two Ghostty windows
  apart — the switcher spawns/tracks its own by window id instead.
- **Slot overlaps are intentional**: both `topRight` (Helium Dev + switcher
  Ghostty) and `mainMax` (Helium Work + Slack) are shared frames — apps that
  live in the same spot on different Spaces.
- **Screen names are machine-specific** (`config.screens`). On a new machine,
  run `hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'`
  and update them; unmatched names fall back to primary.

## Extending

- New app: add to `config.apps` (`{ app=, titleSuffix?, profileDir?, launch? }`).
- New slot: add to `config.slots` (fractions of a screen).
- New profile: add to `config.profiles` with its own `modifier`+`key` — it
  auto-binds. `place` order matters: earlier entries reserve their window first.
- Unrelated Hammerspoon features: new sibling folder + `require("folder.mod")`.
