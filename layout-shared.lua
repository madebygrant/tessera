-- layout-shared.lua
--
-- Shared glue for the tessera tools: screen/geometry resolution, the frame
-- clamp, app/window lookup across an app's processes, and the two channels the
-- feature modules talk over instead of requiring each other -- a window
-- registry and the active-profile broadcast. Pure utilities: no config
-- knowledge lives here.

local core = {}

-- Resolve a screen from a name substring (or a function returning a screen).
-- Falls back to the primary screen if nothing matches, so an unplugged monitor
-- degrades gracefully instead of erroring.
function core.resolveScreen(spec)
  if type(spec) == "function" then return spec() end
  if spec then
    for _, s in ipairs(hs.screen.allScreens()) do
      local name = s:name()
      if name and name:find(spec, 1, true) then return s end
    end
  end
  return hs.screen.primaryScreen()
end

-- A frame computed as fractions (0..1) of a screen's usable area (:frame()
-- excludes the menu bar / Dock). spec = { screen, x, y, w, h, inset, gap }:
--   inset = { top, bottom, left, right } in pixels carved off the screen first
--           -- use it to clear overlays macOS doesn't report, like Sketchybar.
--   gap   = pixels shrunk off EACH edge of the resulting slot, so adjacent
--           slots sit `2*gap` apart (and `gap` from the screen edge). Absorbs
--           apps that snap to a min/cell size slightly larger than the slot.
-- Returns a fresh table each call, so callers can't share/mutate one.
function core.frameFor(spec)
  local f = core.resolveScreen(spec.screen):frame()
  local i = spec.inset or {}
  local x0 = f.x + (i.left or 0)
  local y0 = f.y + (i.top or 0)
  local w0 = f.w - (i.left or 0) - (i.right or 0)
  local h0 = f.h - (i.top or 0) - (i.bottom or 0)
  local g = spec.gap or 0
  return {
    x = x0 + w0 * (spec.x or 0) + g,
    y = y0 + h0 * (spec.y or 0) + g,
    w = w0 * (spec.w or 1) - 2 * g,
    h = h0 * (spec.h or 1) - 2 * g,
  }
end

-- Keep a window from bleeding past its screen's RIGHT edge onto a side-by-side
-- neighbour screen (the original Ghostty-onto-the-laptop bug). An app that snaps
-- wider than its slot gets shifted left, back onto its own screen. Vertical
-- overflow is deliberately left alone: a too-tall window falls off the bottom
-- edge (harmless -- nothing below) rather than being pushed UP into the slot
-- above it, which would overlap a flush neighbour.
local function clampInto(win)
  local f = win:frame()
  local s = win:screen():frame()
  if f.x + f.w > s.x + s.w then
    win:setTopLeft({ x = s.x + s.w - f.w, y = f.y })
  end
end

-- Set a window's frame, then clamp it back onto its screen. Apps that snap to a
-- min/cell grid (Ghostty) resize a beat AFTER setFrame returns, so an immediate
-- clamp sees the not-yet-grown size and misses -- re-clamp on a short delay to
-- catch the settled size.
function core.setFrameClamped(win, target)
  win:setFrame(target)
  clampInto(win)
  hs.timer.doAfter(0.15, function() clampInto(win) end)
  hs.timer.doAfter(0.4, function() clampInto(win) end)
end

-- True if `s` ends with `suffix`. Empty suffix matches anything.
function core.endsWith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

-- True if the title ends with ANY of the suffixes. Used to spot a window that
-- a titled entry has claimed, so an untitled one leaves it alone.
function core.endsWithAny(s, suffixes)
  for _, suffix in ipairs(suffixes or {}) do
    if core.endsWith(s, suffix) then return true end
  end
  return false
end

-- App name -> bundle id, learned the first time we see the app running. Lets
-- every later lookup take the indexed applicationsForBundleID path instead of
-- walking the process table.
local bundleIds = {}

-- EVERY running app object for a name or bundle id. macOS happily hosts two
-- processes for one app -- the `open -na` an entry's `launch`/`profileDir` runs
-- forks a fresh instance -- and hs.application.get returns just one of them
-- (often the newest). Anything hunting for a window has to look across all of
-- them or it silently misses the other instance's windows.
--
-- Called from the 0.2s pollers and from window-layout's retries, so the slow
-- path matters: config entries name apps ("Ghostty"), not bundle ids, and only
-- a bundle id can be looked up directly. Put a bundle id in the config to skip
-- the scan entirely even before the app is running.
function core.apps(name)
  local found = hs.application.applicationsForBundleID(bundleIds[name] or name)
  if #found > 0 then return found end
  local out = {}
  for _, a in ipairs(hs.application.runningApplications()) do
    if a:name() == name or a:bundleID() == name then
      out[#out + 1] = a
      bundleIds[name] = a:bundleID()
    end
  end
  return out
end

-- Every standard window of an app, across all its processes.
function core.appWindows(name)
  local wins = {}
  for _, a in ipairs(core.apps(name)) do
    for _, w in ipairs(a:allWindows()) do
      if w:isStandard() then wins[#wins + 1] = w end
    end
  end
  return wins
end

-- Stable key for a placed window: app + title suffix. Shared so the switcher
-- (which publishes) and window-layout (which reads) build identical keys.
function core.entryKey(app, suffix)
  return app .. "\0" .. (suffix or "")
end

-- Window registry: one module publishes a live window under an entryKey, the
-- other resolves it later. Replaces window-layout's require() of the switcher.
local registry = {} -- entryKey -> window id

function core.publishWindow(key, win)
  registry[key] = win and win:id() or nil
end

function core.window(key)
  local id = registry[key]
  return id and hs.window.get(id) or nil
end

-- Active-profile broadcast: window-layout announces the profile it just applied,
-- the switcher retargets itself to that profile's switcher block. Same
-- decoupling as the registry -- neither module requires the other.
local profileHandlers = {}
local activeProfile = nil

function core.onProfile(fn)
  profileHandlers[#profileHandlers + 1] = fn
end

function core.setProfile(name)
  if name == activeProfile then return end
  activeProfile = name
  for _, fn in ipairs(profileHandlers) do fn(name) end
end

function core.profile()
  return activeProfile
end

return core
