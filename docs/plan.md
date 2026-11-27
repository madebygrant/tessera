# Tessera: remaining waves

Port of the Hammerspoon tessera to a native app. Phase 1 (engine, profiles,
switcher) and the event-driven, testable core are done. Each wave below lands
on its own and leaves `make test` passing.

## Wave 1: Slot move [done 2026-11-27]

Send the focused window, whatever app owns it, to one of the active
profile's slots.

- `keys.slotMove`+1..N, gated by a `slotMove` block (`enabled = false` turns
  it off; no block means off).
- Key order: the profile's `slots` list, else the slots its `place` entries
  name in order of first appearance.
- Bound for the longest list across profiles; a key past the active
  profile's count does nothing.
- Validation: `slotMove` on requires `keys.slotMove`.

Exit criterion: `make test` passes, including tests for slot order, the
no-op past the count, and the gate.

## Wave 2: Overlay

Hold `keys.switcher` or `keys.slotMove` alone for `overlay.delay` and boxes
show the active profile's slots and what each key does. Release hides it; a
key press first makes it a chord.

- CGEventTap on flagsChanged/keyDown, with a watchdog because macOS disables
  slow taps.
- Skip the anchor box when the anchor and other slots share a frame.
- Risk: an event tap needs Input Monitoring permission on top of
  Accessibility.

Exit criterion: `make test` passes; the overlay shows on hold and hides on
release or chord.

## Wave 3: Sketchybar trigger and CLI

- Push `APP INDEX COUNT PROFILE MAXIMIZED APP_NAME ANCHOR_NAME FOCUSED` to
  `sketchybar --trigger <event>` on every switch, maximize and profile change.
- A `tessera` CLI (status, cycle with a 0.4s throttle, push) so the bar no
  longer calls `hs`.
- Update the vendored bar plugin to use the CLI.

Exit criterion: the bar updates on a switch and scrolling on it cycles apps.

## Wave 4: Launch at login

- Register with `SMAppService.mainApp`; a menu toggle.

Exit criterion: Tessera is running after logging out and back in.

## Wave 5: Small fixes

- Reload the config when the file changes.
- Check for hotkey collisions at load and name both sides of a clash.
- Map keys through the active layout (`UCKeyTranslate`).
- Import Hammerspoon's saved profile per screen setup, once.
- A dedicated signing certificate instead of "Tenure Local".
  Risk: changing the identity drops the Accessibility grant once.

Exit criterion: `make test` passes and each item is checked by hand.

## Wave 6: Settings window

SwiftUI editor over the `Config` model: screens picked from connected
displays, a slot canvas, a key recorder with collision warnings, app
pickers, profile editor. Stores plain JSON (comments are lost on save).

Exit criterion: editing in the window and saving round-trips the config, and
the engine reloads it.
