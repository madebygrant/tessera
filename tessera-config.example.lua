-- tessera-config.example.lua
--
-- Template config for the tessera tools. Copy it to one of the two places
-- tessera looks, then edit the values for your machine (screen names, apps,
-- slots, profiles). Either way it stays out of version control.
--
--   cp tessera-config.example.lua ~/.hammerspoon/tessera-config.lua  -- preferred
--   cp tessera-config.example.lua config.lua                         -- in-repo
--
-- Outside the repo wins if both exist, and survives re-cloning tessera.

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
  leftHalf   = { screen = "external", x = 0,   y = 0,    w = 0.5,  h = 1    },
  rightHalf  = { screen = "external", x = 0.5, y = 0,    w = 0.5,  h = 1    },
  mainMax    = { screen = "main",     x = 0,   y = 0,    w = 1,    h = 1    },
  full       = { screen = "external", x = 0,   y = 0,    w = 1,    h = 1    },
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

-- Title suffixes other entries have claimed for the same app. An untitled entry
-- matches ANY window of its app, so without this it could hijack a titled
-- sibling's window; these are the suffixes it must skip.
function C.reservedSuffixes(appName)
  local out = {}
  for _, a in pairs(C.apps) do
    if a.app == appName and a.titleSuffix then out[#out + 1] = a.titleSuffix end
  end
  return out
end

-- ================= SWITCHER =================
-- The switcher's hotkey layer, shared by every profile: these keys never
-- rebind, only what they target changes (each profile's `switcher` block says
-- which apps and slots they drive).
--   modifier+1..N        -- jump to the Nth app of the active profile
--   modifier+Left/Right  -- cycle through them
--   modifier+maximizeKey -- toggle the current one full-screen
C.switcher = {
  modifier    = { "ctrl", "alt", "cmd" },
  maximizeKey = "f",
}

-- ================= PROFILES =================
-- Full-desktop layouts, each bound to a hotkey. A `place` entry positions one
-- app in one slot. `useSwitcherWindow` reuses the switcher's tracked window for
-- that app. Order matters: earlier entries reserve their window first.
--
-- `switcher` retargets the shared hotkeys while this profile is active:
--   anchor/anchorSlot -- the app pinned beside the cycled ones
--   otherSlot         -- where the cycled apps land
--   fullSlot          -- the maximize target
--   apps              -- what modifier+1..N cycles through
C.profiles = {
  dev = {
    modifier = { "ctrl", "alt", "cmd" }, key = "L",
    switcher = {
      anchor = "editor", anchorSlot = "topLeft",
      otherSlot = "topRight", fullSlot = "full",
      apps = { "browser", "terminal" },
    },
    place = {
      { app = "browser",  slot = "topRight" },
      { app = "terminal", slot = "topRight",   useSwitcherWindow = true },
      { app = "terminal", slot = "bottomWide" },
      { app = "editor",   slot = "topLeft" },
      { app = "chat",     slot = "mainMax" },
    },
  },

  -- Same apps, but the external screen is two full-height halves.
  split = {
    modifier = { "ctrl", "alt", "cmd" }, key = "K",
    switcher = {
      anchor = "editor", anchorSlot = "leftHalf",
      otherSlot = "rightHalf", fullSlot = "full",
      apps = { "browser", "terminal" },
    },
    place = {
      { app = "browser",  slot = "rightHalf" },
      { app = "terminal", slot = "rightHalf", useSwitcherWindow = true },
      { app = "editor",   slot = "leftHalf" },
      { app = "chat",     slot = "mainMax" },
    },
  },
}

-- The profile the switcher targets at load, before any profile hotkey is used.
C.defaultProfile = "dev"

function C.profile(name)
  local p = C.profiles[name]
  assert(p, "unknown profile: " .. tostring(name))
  return p
end

return C
