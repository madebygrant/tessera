-- config.example.lua
--
-- Template config for the tessera tools. Copy this to `config.lua` and edit the
-- values for your machine (screen names, apps, slots, profiles). `config.lua`
-- is gitignored so your local setup stays out of version control.
--
--   cp config.example.lua config.lua
--
-- The other modules only read from config.lua.

local core = require("tessera.layout-shared")

local C = {}

-- ================= SCREENS =================
-- Friendly name -> a substring of the hs.screen name (see `hs.screen.allScreens`).
-- Anything that doesn't match falls back to the primary screen.
--   hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'
C.screens = {
  main     = "Built-in Retina Display",
  external = "YOUR_EXTERNAL_MONITOR_NAME",
}

-- Pixels carved off a screen's edges before slots are computed -- for overlays
-- macOS doesn't report in :frame(), like a status bar. Keyed by friendly name.
C.screenInsets = {
  -- external = { top = 28 }, -- e.g. clear a top status bar
}

-- Pixels shrunk off each slot edge, so neighbours sit 2*gap apart. Raise for
-- spacing between windows; 0 = flush, edge-to-edge.
C.gap = 0

-- ================= SLOTS =================
-- A slot is a screen + a rectangle in FRACTIONS (0..1) of that screen's usable
-- area. No pixel math, and it follows the monitor if resolution changes.
C.slots = {
  topLeft    = { screen = "external", x = 0,   y = 0,    w = 0.5,  h = 0.75 },
  topRight   = { screen = "external", x = 0.5, y = 0,    w = 0.5,  h = 0.75 },
  bottomWide = { screen = "external", x = 0,   y = 0.75, w = 1,    h = 0.25 },
  mainMax    = { screen = "main",     x = 0,   y = 0,    w = 1,    h = 1    },
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
--   profileDir -- Chromium-based: open with a specific profile in a new window
--   launch     -- a raw shell command (wins over profileDir)
-- `app` is the app name or bundle id.
C.apps = {
  editor   = { app = "Zed" },
  terminal = { app = "Ghostty" },
  browser  = { app = "YourBrowser", titleSuffix = "Work", profileDir = "Default" },
  chat     = { app = "Slack" },
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
  anchor     = "editor",
  anchorSlot = "topLeft",
  otherSlot  = "topRight",
  apps       = { "browser", "terminal" },
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
      { app = "browser",  slot = "topRight" },
      { app = "terminal", slot = "topRight",   useSwitcherWindow = true },
      { app = "terminal", slot = "bottomWide" },
      { app = "editor",   slot = "topLeft" },
      { app = "chat",     slot = "mainMax" },
    },
  },
}

return C
