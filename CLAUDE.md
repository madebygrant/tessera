# tessera — Hammerspoon window layout

Config-driven window management: a half-screen app switcher plus named
full-desktop layout profiles, both placing windows into geometry-based "slots".

Loaded from `~/.hammerspoon/init.lua` via `require("tessera")`, which resolves to
`tessera/init.lua` and wires up the feature modules. Reload after edits:
menu-bar Hammerspoon → Reload Config (or `hs.reload()`).

## Files

- **init.lua** — package entry point (`require("tessera")`). Resolves the config
  (plain error if there is none), attaches the schema, then loads the feature
  modules in order, optional ones only when `schema.enabled` says so. Returns
  the config table.
- **the config** — the ONE file to edit: screens, slots, insets, gap, apps,
  keys, feature blocks, and layout profiles. Data only, no functions; the
  accessors come from `schema.lua`. `tessera-config.example.lua` is the
  template. It loads from either of two places, first hit wins:
  1. `~/.hammerspoon/tessera-config.lua` — outside the repo, so it survives
     re-cloning. Preferred, and what this machine uses.
  2. `tessera/config.lua` — inside the repo, gitignored.

  Both resolve because `~/.hammerspoon` is first on Hammerspoon's
  `package.path`. `init.lua` requires whichever it finds and then sets
  `package.loaded["tessera-config"]` to it, so the feature modules can just say
  `require("tessera-config")` without caring which file won. With both present
  it prints which one it used.
- **schema.lua** — the accessors every config needs (`slot`, `app`, `profile`,
  `reservedSuffixes`) plus `enabled(config, name)`. `init.lua` attaches them
  after loading the config, so the config file stays data-only and a fix to an
  accessor reaches every config. Asserts the `keys` block is there, since every
  module binds off it.
- **layout-shared.lua** — pure engine: screen/geometry resolution
  (`frameFor`, `resolveScreen`), the frame clamp (`setFrameClamped`), the
  cross-module window registry (`publishWindow`/`window`), the active-profile
  broadcast (`setProfile`/`onProfile`/`profile`), `entryKey`, `endsWith`.
  No config knowledge.
- **layout-workspace.lua** — the half-screen switcher. Pins the active profile's
  `switcher.anchor` to its `anchorSlot`; hotkeys cycle that profile's
  `switcher.apps` through `otherSlot` (`keys.switcher`+1..N, and
  +Left/Right). `keys.switcher`+`keys.maximize` toggles the current workspace app
  between `otherSlot` and `fullSlot` (whole screen); switching apps resets it.
  Publishes each placed window to the registry, and retargets itself on the
  profile broadcast.
- **sketchybar/** — the bar half of the readout (`items/` + `plugins/`), copied
  or symlinked into `~/.config/sketchybar`. Not loaded by Hammerspoon at all.
- **slot-move.lua** — sends the FOCUSED window to one of the active profile's
  slots (`keys.slotMove`+1..N), whatever app owns it. Optional, gated by
  `config.slotMove.enabled`, and required by `init.lua` only when on.
- **window-layout.lua** — applies a `config.profiles` entry on its hotkey:
  broadcasts the profile name, then each app → its slot, launching/matching via
  the app's config.

## Key concepts

- **Slots are fractions of a screen**, not pixels: `{ screen, x, y, w, h }` in
  0..1 of that screen's `:frame()`. Resolution-independent; a missing monitor
  falls back to the primary screen. Resolved live via `config.slot(name)`.
- **screenInsets** carve pixels off a screen before slots compute — used to
  clear overlays macOS doesn't report (Sketchybar: `external = { top = 28 }`).
- **gap** shrinks every slot edge by N px (neighbours end up `2*gap` apart).
  Currently `0` (flush, edge-to-edge).
- **All key layers live in `C.keys`** (`switcher`, `slotMove`, `profile`,
  `maximize`), because the way these break is by colliding with each other or
  with an app. Modules read it directly. A profile may carry its own `modifier`
  to sit off the shared layer.
- **The switcher belongs to a profile.** `C.keys.switcher` is only the hotkey
  layer — bound once and never rebound. Each profile
  carries its own
  `switcher = { anchor, anchorSlot, otherSlot, fullSlot, apps, start? }`,
  and applying a profile retargets the live switcher at it. `apps` order is the
  number-key order; optional `start` names which of them the profile opens on
  and resets to, so "first app" and "key 1" can differ. Number keys are
  bound for the WIDEST `apps` list across all profiles; a key past the active
  profile's count is a no-op. `C.defaultProfile` is what the switcher targets at
  load, before any profile hotkey is pressed. Its keys are `ctrl+alt`, kept
  clear of `alt+cmd` — those arrows are tab-switch in most browsers and
  terminals, and Hammerspoon grabs the event first, so binding there breaks them
  silently.
- **Slot move is the escape hatch.** The switcher and profiles only move apps
  named in the config; `slot-move` takes whatever window has focus and drops it
  in a slot, so an app tessera has never heard of still lands somewhere sane.
  Its key order is the profile's optional `slots` list, else the slots its
  `place` entries name in order of first appearance. Like the switcher's number
  keys it binds for the longest list across all profiles and no-ops past the
  active one's count, and it retargets on the profile broadcast.
- **Profile broadcast** is the second decoupler: `window-layout` calls
  `core.setProfile(name)` before placing; `layout-workspace` subscribed with
  `core.onProfile`. Same-name calls are ignored, so re-pressing the active
  profile's hotkey re-places windows without resetting the switcher's index.
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
  GLOBAL to the instance, so you can't title-match to tell two plain Ghostty
  windows apart — the switcher tracks its window by id in the registry instead.
- **The switcher never opens a second window.** It reuses the registry window,
  else adopts any window the app already has (so an app launched at login is
  moved, not duplicated), else launches the app. Only window-layout spawns, and
  only when a profile puts the same app in two slots and every existing window
  is already used by an earlier `place` entry.
- **Don't preload a command in Ghostty.** Tried and reverted: macOS has no way to
  tell a RUNNING Ghostty to open a window with a command (`+new-window` is
  Linux-only in 1.3.1; `--args` are ignored for a live instance), so it needs
  `open -n` and a second process. Worse, Ghostty pops a modal —
  *Allow Ghostty to execute "…"?* — for any command arriving as a CLI arg, with
  no config key to suppress it and no "don't ask again", which rules the whole
  approach out for unattended use. Passing the command via a dedicated
  `--config-file` (`command = …`) skips the modal but launched the program in a
  state where it exited immediately; not pursued.
- **An app can span processes**, so never use `hs.application.get` — it returns
  only one of them, often the newest. Any entry with `launch`/`profileDir` runs
  `open -na`, which forks a fresh instance (this is how the Helium profiles
  open). `core.apps(name)` / `core.appWindows(name)` gather every process;
  all lookups go through those.
- **Untitled entries must skip titled siblings' windows.** An entry with no
  `titleSuffix` (plain `ghostty`) matches ANY window of its app, so it could
  claim a titled sibling's. `config.reservedSuffixes(appName)` lists the suffixes
  other entries for that app claim, and the untitled lookups (`plainWindow`,
  `findWindow`) filter them out. Currently inert — no app has both a titled and
  an untitled entry — but it makes adding one safe with no extra config.
- **Slot overlaps are intentional**: both `topRight` (Helium Dev + switcher
  Ghostty) and `mainMax` (Helium Work + Slack) are shared frames — apps that
  live in the same spot on different Spaces.
- **Optional features are opt-in, one rule.** `schema.enabled(config, name)`
  decides: the block has to exist, and `enabled = false` turns it off. No block
  means off, so the config file lists everything that runs. `sketchybar` and
  `slotMove` both go through it; anything added later should too.
- **Sketchybar readout.** Gated by `config.sketchybar` (`enabled`/`event`/`bin`).
  `layout-workspace` shells `sketchybar --trigger <event>` on every switch,
  maximize and profile change, carrying
  `APP INDEX COUNT PROFILE MAXIMIZED APP_NAME ANCHOR_NAME FOCUSED`. The bar
  shows the profile plus the slot number, and drops the number while the front
  app is neither the current cycled app nor the anchor. `FOCUSED` is false for a
  profile retarget, which places nothing and so must not claim the front app.
  The bar side is vendored in `sketchybar/`, symlinked from
  `~/.config/sketchybar/{items,plugins}/tessera.sh` on this machine, so edit the
  repo copy. It keeps its own state under `$TMPDIR` because SketchyBar runs each
  event in a separate process; `TESSERA_LABEL_COLOR` is the only theming hook.
  Missing sketchybar is a no-op, so the trigger is safe on a machine without
  it. The `hs.task` handles are retained in `barTasks` — an unreferenced one gets
  collected mid-flight and the update silently goes missing. `M.pushToBar()` is
  exported so the bar can pull current state when IT restarts.
- **VoiceOver eats the switcher.** `ctrl+alt` is VoiceOver's VO modifier, so
  every switcher hotkey stops working while VoiceOver is on (cmd+F5). Nothing
  errors, the keys just do nothing. If they go dead for no reason, check that
  first.
- **Screen names are machine-specific** (`config.screens`). On a new machine,
  run `hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'`
  and update them; unmatched names fall back to primary.

## Extending

- New app: add to `config.apps` (`{ app=, titleSuffix?, profileDir?, launch? }`).
- New slot: add to `config.slots` (fractions of a screen).
- New profile: add to `config.profiles` with a `key` — it auto-binds on
  `keys.profile`, or on its own `modifier` if it names one. `place` order
  matters: earlier entries reserve their window first. Give it a `switcher`
  block too; it's required, not optional. A `slots` list is optional and only
  fixes slot-move's key order, which otherwise falls out of `place`.
- New optional feature: give it a config block, gate it on
  `schema.enabled(config, name)`, and require it from `init.lua` behind that.
- Unrelated Hammerspoon features: new sibling folder + `require("folder.mod")`.
