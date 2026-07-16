-- config.lua
--
-- Single declarative config for the tessera tools. Edit THIS file to
-- change screens, slots, apps, the half-screen switcher, or layout profiles --
-- the other modules just read from here.

local core = require("tessera.layout-shared")

local C = {}

-- ================= SCREENS =================
-- Friendly name -> a substring of the hs.screen name (see `hs.screen.allScreens`).
-- Anything that doesn't match falls back to the primary screen.
C.screens = {
  main     = "Built-in Retina Display",
  external = "LF32TU87",
}

-- Pixels carved off a screen's edges before slots are computed -- for overlays
-- macOS doesn't report in :frame(), like Sketchybar. Keyed by friendly name.
C.screenInsets = {
  external = { top = 28 }, -- clear the Sketchybar bar at the top
}

-- Pixels shrunk off each slot edge, so neighbours sit 2*gap apart. Raise for
-- spacing between windows; 0 = flush, edge-to-edge.
C.gap = 0

-- ================= SLOTS =================
-- A slot is a screen + a rectangle in FRACTIONS (0..1) of that screen's usable
-- area. No pixel math, and it follows the monitor if resolution changes.
C.slots = {
  topLeft    = { screen = "external", x = 0,   y = 0,    w = 0.5,  h = 0.75 },
  -- Slightly narrower than a half: leaves a small right margin so Ghostty can
  -- cell-snap a bit wider without its clamped right edge shoving the window
  -- left across the topLeft boundary (into Zed).
  topRight   = { screen = "external", x = 0.5, y = 0,    w = 0.49, h = 0.75 },
  bottomWide = { screen = "external", x = 0,   y = 0.75, w = 1,   h = 0.25 },
  mainMax    = { screen = "main",     x = 0,   y = 0,    w = 1,   h = 1    },
}

-- Live frame for a slot, computed fresh each call (handles monitor changes).
function C.slot(name)
  local s = C.slots[name]
  assert(s, "unknown slot: " .. tostring(name))
  return core.frameFor({
    screen = C.screens[s.screen] or s.screen,
    inset = C.screenInsets[s.screen],
    gap = C.gap,
    x = s.x, y = s.y, w = s.w, h = s.h,
  })
end

-- ================= APPS =================
-- How to identify a window (titleSuffix) and how to open one when missing:
--   profileDir -- Chromium/Helium: open with a specific profile in a new window
--   launch     -- a raw shell command (wins over profileDir)
-- `app` is the app name or bundle id.
C.apps = {
  zed        = { app = "Zed" },
  ghostty    = { app = "Ghostty" },
  heliumDev  = { app = "Helium", titleSuffix = "Development", profileDir = "Default" },
  heliumWork = { app = "Helium", titleSuffix = "Work",        profileDir = "Profile 1" },
  slack      = { app = "Slack" },
}

function C.app(ref)
  local a = C.apps[ref]
  assert(a, "unknown app: " .. tostring(ref))
  return a
end

-- ================= SWITCHER =================
-- Half-screen app switcher: an anchor app pinned to `anchorSlot`, plus apps
-- cycled through `otherSlot` via hotkeys (modifier+1..N, and modifier+Left/Right).
C.switcher = {
  anchor     = "zed",
  anchorSlot = "topLeft",
  otherSlot  = "topRight",
  apps       = { "heliumDev", "ghostty" },
  modifier   = { "ctrl", "alt", "cmd" },
}

-- ================= PROFILES =================
-- Full-desktop layouts, each bound to a hotkey. A `place` entry positions one
-- app in one slot. `useSwitcherWindow` reuses the switcher's tracked window for
-- that app. Order matters: earlier entries reserve their window first.
C.profiles = {
  dev = {
    modifier = { "ctrl", "alt", "cmd" }, key = "L",
    place = {
      { app = "heliumDev",  slot = "topRight" },
      { app = "heliumWork", slot = "mainMax" },
      { app = "ghostty",    slot = "topRight",   useSwitcherWindow = true },
      { app = "ghostty",    slot = "bottomWide" },
      { app = "zed",        slot = "topLeft" },
      { app = "slack",      slot = "mainMax" },
    },
  },
}

return C
