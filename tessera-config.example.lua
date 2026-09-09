-- tessera-config.example.lua
--
-- Copy this, then edit your copy for your machine: screen names, apps, slots,
-- keys, profiles. Either spot works and both stay out of version control.
--
--   cp tessera-config.example.lua ~/.hammerspoon/tessera-config.lua  -- preferred
--   cp tessera-config.example.lua config.lua                         -- in-repo
--
-- The one outside the repo wins if both exist, and survives re-cloning tessera.
-- It's all data, nothing to call. A feature stays off until its block is here,
-- and `enabled = false` turns one off without deleting it.

local C = {}

-- ================= SCREENS =================
-- Your name for a screen -> enough of its real name to match it. Anything that
-- doesn't match falls back to the primary screen.
--   hs -c 'for _,s in ipairs(hs.screen.allScreens()) do print(s:name()) end'
C.screens = {
  main     = "Built-in Retina Display",
  external = "YOUR_EXTERNAL_MONITOR_NAME",
}

-- Pixels to keep clear at a screen's edges. macOS doesn't mention overlays
-- like a status bar, so say so here and slots will avoid them.
C.screenInsets = {
  -- external = { top = 28 }, -- e.g. clear a top status bar
}

-- Breathing room around every slot, in pixels. Neighbours end up 2*gap apart.
-- 0 is flush, edge to edge.
C.gap = 0

-- ================= SLOTS =================
-- A slot is a rectangle on a screen, measured in fractions of it rather than
-- pixels, so it survives a resolution change. x/y is the top-left corner.
C.slots = {
  topLeft    = { screen = "external", x = 0,   y = 0,    w = 0.5,  h = 0.75 },
  topRight   = { screen = "external", x = 0.5, y = 0,    w = 0.5,  h = 0.75 },
  bottomWide = { screen = "external", x = 0,   y = 0.75, w = 1,    h = 0.25 },
  leftHalf   = { screen = "external", x = 0,   y = 0,    w = 0.5,  h = 1    },
  rightHalf  = { screen = "external", x = 0.5, y = 0,    w = 0.5,  h = 1    },
  mainMax    = { screen = "main",     x = 0,   y = 0,    w = 1,    h = 1    },
  full       = { screen = "external", x = 0,   y = 0,    w = 1,    h = 1    },
}

-- ================= APPS =================
-- Your name for an app -> how to find its window, and how to open one if it
-- isn't there yet.
--   app         the app's name, or its bundle id
--   titleSuffix pick one specific window by how its title ends
--   profileDir  Chromium-based: open this profile in its own window
--   launch      run this command instead (wins over profileDir)
C.apps = {
  editor   = { app = "Zed" },
  terminal = { app = "Ghostty" },
  browser  = { app = "YourBrowser", titleSuffix = "Work", profileDir = "Default" },
  chat     = { app = "Slack" },
}

-- ================= KEYS =================
-- Every shortcut in one place, so you can spot a clash before it bites.
--   switcher +1..N, +Left/Right   the active profile's apps
--   switcher +maximize            fill the screen with the current one
--   slotMove +1..N                throw the focused window into a slot
--   profile  +its own key         apply that layout
-- Steer clear of alt+cmd. Its arrows switch tabs in most browsers and
-- terminals, and Hammerspoon gets the key first, so they'd quietly stop
-- working.
C.keys = {
  switcher = { "ctrl", "alt" },
  slotMove = { "ctrl", "alt", "shift" },
  profile  = { "ctrl", "alt", "cmd" },
  maximize = "f",
}

-- ================= SKETCHYBAR =================
-- Shows the active profile and slot in Sketchybar. tessera only sends the
-- event; the item that draws it lives in your Sketchybar config, copied from
-- sketchybar/ in the repo. Delete this block if you don't use Sketchybar.
--   event  match the `--add event` name on the bar side
--   bin    where sketchybar lives, if it's somewhere unusual
C.sketchybar = {
  enabled = false,
  event   = "tessera_switcher",
}

-- ================= SLOT MOVE =================
-- Sends whatever window you're looking at to one of the current profile's
-- slots, even if it belongs to an app tessera has never heard of.
-- Which slot gets which number: the profile's `slots` list if it has one,
-- otherwise the slots its `place` entries mention, in order.
C.slotMove = {
  enabled = false,
}

-- ================= PROFILES =================
-- A whole-desktop layout on one key. `key` rides on C.keys.profile unless the
-- profile names its own `modifier`.
--
-- switcher  what the switcher keys drive while this profile is active:
--   anchor, anchorSlot  the app pinned beside the ones you cycle
--   otherSlot           where the cycled apps land
--   fullSlot            where maximize puts them
--   apps                what +1..N cycles through, in that order
--   start               which of them to open on (default: the first)
--
-- slots     numbering for slotMove. Optional; `place` decides it otherwise.
-- place     where each app goes when you press the profile's key. Earlier
--           entries claim their window first, which matters when an app appears
--           twice. useSwitcherWindow reuses the window the switcher tracks.
C.profiles = {
  dev = {
    key = "L",
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
    key = "K",
    switcher = {
      anchor = "editor", anchorSlot = "leftHalf",
      otherSlot = "rightHalf", fullSlot = "full",
      apps = { "browser", "terminal" }, start = "terminal",
    },
    slots = { "leftHalf", "rightHalf", "mainMax" },
    place = {
      { app = "browser",  slot = "rightHalf" },
      { app = "terminal", slot = "rightHalf", useSwitcherWindow = true },
      { app = "editor",   slot = "leftHalf" },
      { app = "chat",     slot = "mainMax" },
    },
  },
}

-- Which profile is live at startup, before you press anything.
C.defaultProfile = "dev"

return C
